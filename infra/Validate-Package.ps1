#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $ScriptDomPath = $env:SQLAI_SCRIPTDOM_PATH
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
foreach ($file in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "PowerShell syntax errors in $($file.Name): $($errors.Message -join '; ')"
    }
}

& node --test (Join-Path $PSScriptRoot 'packaging.test.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Packaging contract tests failed.' }

$compiled = Join-Path ([IO.Path]::GetTempPath()) ("sqlai-arm-{0}.json" -f [guid]::NewGuid())
$sql = Join-Path ([IO.Path]::GetTempPath()) ("sqlai-validation-{0}.sql" -f [guid]::NewGuid())
try {
    & az bicep build --file (Join-Path $PSScriptRoot 'main.bicep') --outfile $compiled
    if ($LASTEXITCODE -ne 0) { throw 'Bicep compilation failed.' }
    $actual = (Get-Content -Raw -LiteralPath $compiled).Replace("`r`n", "`n").Trim()
    $expected = (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'main.json')).Replace("`r`n", "`n").Trim()
    if ($actual -cne $expected) {
        throw 'main.json is stale or the Bicep compiler differs. Rebuild using the documented compiler and rerun.'
    }
    & (Join-Path $PSScriptRoot 'Initialize-Lab.ps1') -Server 'sqlai-validation-cu.database.windows.net' `
        -FoundryEndpoint 'https://foundry-validation-cu.services.ai.azure.com' -IncludeChat -GenerateOnly -OutputPath $sql

    if ([string]::IsNullOrWhiteSpace($ScriptDomPath)) {
        $ScriptDomPath = Join-Path $HOME '.nuget\packages\microsoft.sqlserver.transactsql.scriptdom\180.18.1\lib\net8.0\Microsoft.SqlServer.TransactSql.ScriptDom.dll'
    }
    if (-not (Test-Path -LiteralPath $ScriptDomPath -PathType Leaf)) {
        throw 'ScriptDom 180 is required to validate generated SQL; set SQLAI_SCRIPTDOM_PATH or restore the workshop validation prerequisite.'
    }
    Add-Type -Path $ScriptDomPath
    $parser = [Microsoft.SqlServer.TransactSql.ScriptDom.TSql180Parser]::new(
        $true, [Microsoft.SqlServer.TransactSql.ScriptDom.SqlEngineType]::SqlAzure)
    $reader = [IO.StringReader]::new((Get-Content -Raw -LiteralPath $sql))
    try {
        $errors = $null
        $null = $parser.Parse($reader, [ref]$errors)
        if ($errors.Count -gt 0) {
            throw "Generated SQL syntax errors: $(($errors | ForEach-Object { "line $($_.Line): $($_.Message)" }) -join '; ')"
        }
    } finally {
        $reader.Dispose()
    }
    Write-Output 'PASS: packaging contracts, PowerShell syntax, Bicep compilation, ARM parity, and generated T-SQL syntax. No Azure resources or SQL connections were created.'
} finally {
    foreach ($file in @($compiled, $sql)) {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
    }
}
