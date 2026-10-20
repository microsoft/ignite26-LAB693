#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResourceGroup,
    [Parameter(Mandatory)]
    [string] $DeploymentName,
    [switch] $GenerateOnly,
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-AzJson([string[]] $Arguments) {
    $json = & az @Arguments --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed (exit $LASTEXITCODE): az $($Arguments -join ' ')"
    }
    return $json | ConvertFrom-Json
}

$null = Get-Command az -ErrorAction Stop
$deployment = Invoke-AzJson @('deployment', 'group', 'show', '--resource-group', $ResourceGroup, '--name', $DeploymentName)
if ($deployment.properties.provisioningState -ne 'Succeeded') {
    throw 'The infrastructure deployment must succeed before SQL initialization.'
}
$outputs = $deployment.properties.outputs
$account = Invoke-AzJson @('cognitiveservices', 'account', 'show', '--resource-group', $ResourceGroup, '--name', $outputs.foundryAccountName.value)
$endpointValues = @($account.properties.endpoint)
if ($account.properties.PSObject.Properties.Name -contains 'endpoints') {
    $endpointValues += @($account.properties.endpoints.PSObject.Properties | ForEach-Object { $_.Value })
}
$endpoints = @($endpointValues | Where-Object {
    $_ -is [string] -and $_.TrimEnd('/') -cmatch '^https://foundry-[a-z0-9-]+-cu\.services\.ai\.azure\.com$'
} | ForEach-Object { $_.TrimEnd('/') } | Sort-Object -Unique)
if ($endpoints.Count -ne 1) {
    throw 'Azure metadata did not return exactly one notebook-compatible resource-level Foundry endpoint. Inspect the account; do not guess an endpoint.'
}
if ($outputs.databaseName.value -ne 'Healthcare') {
    throw 'The deployment does not target the dedicated Healthcare database.'
}
& (Join-Path $PSScriptRoot 'Initialize-Lab.ps1') `
    -Server $outputs.sqlServerFqdn.value `
    -FoundryEndpoint $endpoints[0] `
    -IncludeChat:($outputs.includeChat.value -eq $true) `
    -GenerateOnly:$GenerateOnly `
    -OutputPath $OutputPath

if ($GenerateOnly) {
    Write-Output 'Preparation SQL generated from deployment metadata. No SQL was executed.'
    return
}

Write-Output "Open the repository in VS Code, select the MSSQL kernel, and connect with Microsoft Entra to $($outputs.sqlServerFqdn.value), database Healthcare."
Write-Output "Participant entry point: instructions\01-beyond-keywords.ipynb"
Write-Output 'Preparation did not test live inference or DiskANN. Rehearse all four notebooks in a separate instance before distributing this build.'
