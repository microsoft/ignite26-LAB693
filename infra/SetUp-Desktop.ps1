#Requires -Version 7.2
[CmdletBinding()]
param(
    [switch] $Install
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) {
    throw 'This setup targets the skilling provider Windows desktop.'
}

function Update-ProcessPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Install-Tool([string] $PackageId) {
    if (-not $Install) {
        throw "Missing or incompatible tool: $PackageId. Rerun with -Install to install it on the image."
    }
    $null = Get-Command winget -ErrorAction Stop
    & winget install --id $PackageId --exact --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "winget installation failed for $PackageId (exit $LASTEXITCODE)."
    }
    Update-ProcessPath
}

foreach ($tool in @(
    @{ Command = 'az'; Package = 'Microsoft.AzureCLI' },
    @{ Command = 'code'; Package = 'Microsoft.VisualStudioCode' },
    @{ Command = 'sqlcmd'; Package = 'Microsoft.Sqlcmd' }
)) {
    if (-not (Get-Command $tool.Command -ErrorAction SilentlyContinue)) {
        Install-Tool $tool.Package
    }
    $null = Get-Command $tool.Command -ErrorAction Stop
}
$sqlcmdHelp = & sqlcmd --help 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $sqlcmdHelp -notmatch 'authentication-method') {
    Install-Tool 'Microsoft.Sqlcmd'
    $sqlcmdHelp = & sqlcmd --help 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $sqlcmdHelp -notmatch 'authentication-method') {
        throw 'An incompatible sqlcmd shadows Go sqlcmd on PATH. Put the Go sqlcmd installation first, reopen the terminal, and rerun this check.'
    }
}
& az version --query '"azure-cli"' -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Azure CLI verification failed.' }
& sqlcmd --version
if ($LASTEXITCODE -ne 0) { throw 'Go sqlcmd verification failed.' }

$extensions = @(& code --list-extensions)
if ($LASTEXITCODE -ne 0) { throw 'Cannot list VS Code extensions. Run setup in the participant desktop account.' }
foreach ($extension in @('ms-mssql.mssql')) {
    if ($extension -notin $extensions) {
        if (-not $Install) { throw "Missing VS Code extension: $extension. Rerun with -Install." }
        & code --install-extension $extension
        if ($LASTEXITCODE -ne 0) { throw "Extension installation failed: $extension." }
    }
}
$extensions = @(& code --list-extensions)
if ($LASTEXITCODE -ne 0 -or 'ms-mssql.mssql' -notin $extensions) {
    throw 'The MSSQL VS Code extension was not installed in this desktop profile.'
}
Write-Output 'Desktop tools and MSSQL extension verified. Open the repository root to use its SQL notebooks.'
Write-Output 'Do not save Azure CLI login tokens or participant credentials into the shared VM image.'
