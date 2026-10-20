#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^sqlai-[a-z0-9-]+-cu\.database\.windows\.net$')]
    [string] $Server,
    [Parameter(Mandatory)]
    [string] $FoundryEndpoint,
    [switch] $IncludeChat,
    [switch] $GenerateOnly,
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$sqlDirectory = Join-Path $PSScriptRoot 'sql'
$endpoint = $FoundryEndpoint.Trim().TrimEnd('/')
if ($endpoint -cnotmatch '^https://foundry-[a-z0-9-]+-cu\.services\.ai\.azure\.com$' -or $endpoint.Length -gt 128) {
    throw 'Use the actual resource-level Foundry endpoint from Azure metadata, matching the notebook naming contract.'
}
if ($GenerateOnly -and -not $OutputPath) {
    throw 'GenerateOnly requires OutputPath. No SQL has been executed.'
}

$schema = Get-Content -Raw -LiteralPath (Join-Path $sqlDirectory '01-schema.sql')
$seed = Get-Content -Raw -LiteralPath (Join-Path $sqlDirectory '02-seed-cases.sql')
$seedStatements = $seed -replace "N?'(?:[^']|'')*'", "''"
if ($seedStatements -match '(?i)\b(?:DELETE|TRUNCATE|DROP)\b') {
    throw 'The seed INSERT contains unexpected destructive statements. Review notebook drift.'
}
$expectedSeed = $seed.Replace('dbo.Cases', '#ExpectedCases')
$modelAccess = Get-Content -Raw -LiteralPath (Join-Path $sqlDirectory '03-model-access.sql')
if ([regex]::Matches($modelAccess, '__FOUNDRY_ENDPOINT__').Count -ne 1) {
    throw 'The local Foundry endpoint input contract changed. Review infra\sql\03-model-access.sql.'
}
$modelAccess = $modelAccess.Replace('__FOUNDRY_ENDPOINT__', $endpoint)
$helper = if ($IncludeChat) {
    Get-Content -Raw -LiteralPath (Join-Path $sqlDirectory '04-chat-helper.sql')
} else { '' }
$readiness = Get-Content -Raw -LiteralPath (Join-Path $sqlDirectory '05-entry-readiness.sql')

$sql = @"
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'Healthcare' OR CONVERT(INT, SERVERPROPERTY('EngineEdition')) <> 5
    THROW 51000, 'Preparation requires a dedicated Healthcare database on Azure SQL Database.', 1;
IF HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'CONTROL') <> 1
    THROW 51000, 'Run preparation as the configured lab Entra administrator.', 1;
IF OBJECT_ID(N'dbo.RetrievalChunks', N'U') IS NOT NULL
    OR OBJECT_ID(N'dbo.RetrievalSearch', N'P') IS NOT NULL
    OR EXISTS (SELECT 1 FROM sys.fulltext_indexes)
    OR EXISTS (SELECT 1 FROM sys.external_models)
    THROW 51000, 'Participant work already exists. Do not initialize or reseed this database; use a fresh lab instance.', 1;
BEGIN TRANSACTION;
GO
$schema
GO
IF EXISTS (SELECT 1 FROM dbo.ComplaintEmbeddings) OR EXISTS (SELECT 1 FROM dbo.SymptomEmbeddings)
    THROW 51000, 'Original workshop embedding tables contain participant data. Use a fresh lab instance.', 1;
SELECT TOP (0) * INTO #ExpectedCases FROM dbo.Cases;
$expectedSeed
IF (SELECT COUNT(*) FROM #ExpectedCases) <> 207
    THROW 51000, 'The authoritative seed no longer contains exactly 207 cases. Review notebook drift.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Cases)
    INSERT INTO dbo.Cases (Id, Age, Sex, Complaint, Symptoms, Diagnosis)
    SELECT Id, Age, Sex, Complaint, Symptoms, Diagnosis FROM #ExpectedCases;
IF EXISTS (SELECT * FROM dbo.Cases EXCEPT SELECT * FROM #ExpectedCases)
    OR EXISTS (SELECT * FROM #ExpectedCases EXCEPT SELECT * FROM dbo.Cases)
    THROW 51000, 'Existing cases differ from the authoritative seed. Refusing to overwrite data.', 1;
DROP TABLE #ExpectedCases;
GO
$modelAccess
GO
$helper
GO
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    THROW 51000, 'Database master key is missing.', 1;
$readiness
GO
COMMIT TRANSACTION;
PRINT 'Prepared starting state verified. No inference calls or participant exercises were executed.';
"@

$temporary = -not $OutputPath
if ($temporary) {
    $OutputPath = Join-Path ([IO.Path]::GetTempPath()) ("sqlai-prepare-{0}.sql" -f [guid]::NewGuid())
}
try {
    Set-Content -LiteralPath $OutputPath -Value $sql -Encoding utf8
    if ($GenerateOnly) {
        Write-Output "Generated SQL: $OutputPath. No SQL has been executed."
        return
    }
    $null = Get-Command az -ErrorAction Stop
    $null = Get-Command sqlcmd -ErrorAction Stop
    $sqlcmdHelp = & sqlcmd -? 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $sqlcmdHelp -notmatch 'authentication-method') {
        throw 'Go sqlcmd with --authentication-method support is required; the ODBC executable is not sufficient.'
    }
    & sqlcmd -S $Server -d Healthcare --authentication-method ActiveDirectoryAzCli -b -l 60 -t 300 -x -i $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "SQL initialization failed (exit $LASTEXITCODE). Uncommitted preparation is rolled back when the connection closes."
    }
} finally {
    if ($temporary -and (Test-Path -LiteralPath $OutputPath)) {
        Remove-Item -LiteralPath $OutputPath
    }
}
