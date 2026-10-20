[CmdletBinding()]
param(
    [string] $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string] $ScriptDomPath = $env:SQLAI_SCRIPTDOM_PATH
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ScriptDomPath)) {
    $ScriptDomPath = Join-Path $HOME '.nuget\packages\microsoft.sqlserver.transactsql.scriptdom\180.18.1\lib\net8.0\Microsoft.SqlServer.TransactSql.ScriptDom.dll'
}
if (-not (Test-Path -LiteralPath $ScriptDomPath -PathType Leaf)) {
    throw 'ScriptDom 180 is required. Restore Microsoft.SqlServer.TransactSql.ScriptDom 180.18.1 to your NuGet cache, or set SQLAI_SCRIPTDOM_PATH to its net8.0 DLL. SQL parsing was not skipped.'
}

Add-Type -Path $ScriptDomPath
$parser = [Microsoft.SqlServer.TransactSql.ScriptDom.TSql180Parser]::new(
    $true, [Microsoft.SqlServer.TransactSql.ScriptDom.SqlEngineType]::SqlAzure)
$script:units = 0
$script:failures = 0

function Test-SqlSource([string] $Source, [string] $Label) {
    $script:units++
    $errors = $null
    $reader = [IO.StringReader]::new($Source)
    try {
        $null = $parser.Parse($reader, [ref]$errors)
    } finally {
        $reader.Dispose()
    }
    foreach ($error in $errors) {
        $script:failures++
        Write-Output "${Label}: T-SQL line $($error.Line), column $($error.Column): $($error.Message)"
    }
}

$notebooks = @(Get-ChildItem -LiteralPath (Join-Path $Root 'instructions') -Filter '*.ipynb' -File -Recurse)
if ($notebooks.Count -ne 4) {
    throw "Expected four attendee SQL notebooks under $Root\instructions; found $($notebooks.Count)."
}
foreach ($file in $notebooks) {
    $notebook = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    for ($index = 0; $index -lt $notebook.cells.Count; $index++) {
        $cell = $notebook.cells[$index]
        $source = $cell.source -join ''
        $label = "$($file.Name) cell $($index + 1)"
        if ($cell.cell_type -eq 'code') {
            Test-SqlSource $source $label
        } else {
            foreach ($snippet in [regex]::Matches($source, '(?im)^```(?:sql|tsql)[^\r\n]*\r?\n([\s\S]*?)^```[ \t]*$')) {
                Test-SqlSource $snippet.Groups[1].Value "$label optional SQL"
            }
        }
    }
}

$sqlDirectory = Join-Path $Root 'infra\sql'
$sqlFiles = @(Get-ChildItem -LiteralPath $sqlDirectory -Filter '*.sql' -File -Recurse)
if ($sqlFiles.Count -eq 0) {
    throw "No setup SQL files found under $sqlDirectory."
}
foreach ($file in $sqlFiles) {
    Test-SqlSource (Get-Content -Raw -LiteralPath $file.FullName) $file.Name
}

if ($script:failures -gt 0) {
    throw "SQL syntax validation failed: $script:failures errors across $script:units units. Nothing was executed."
}
Write-Output "PASS: $script:units attendee SQL cells/snippets and setup SQL files parsed with ScriptDom 180. Nothing was executed."
