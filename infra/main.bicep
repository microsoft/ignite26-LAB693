targetScope = 'resourceGroup'

@description('Azure region with SQL vector-search support and quota for both selected model versions.')
param location string = 'centralus'

@description('Unique lowercase letters/numbers/hyphens identifying one isolated lab instance.')
@minLength(3)
@maxLength(40)
param labId string = uniqueString(resourceGroup().id)

@description('Object ID of the participant Entra user or dedicated lab administrator group.')
param administratorObjectId string

@description('Display name or UPN of the Entra administrator.')
param administratorName string

@allowed(['User', 'Group'])
param administratorType string = 'User'

@description('First public IPv4 address of the skilling desktop egress range. No wildcard default.')
param desktopStartIpAddress string

@description('Last public IPv4 address of the skilling desktop egress range; use the same address for one IP.')
param desktopEndIpAddress string

@description('Include the optional notebook 4 intent exercise.')
param includeChat bool = true

@allowed(['DataZoneStandard', 'GlobalStandard'])
@description('GlobalStandard is an explicit change in inference processing boundary, never a fallback.')
param modelDeploymentSku string = 'DataZoneStandard'

@minValue(1)
param embeddingCapacity int = 100

@minValue(1)
param chatCapacity int = 100

param embeddingModelVersion string = '1'
param chatModelVersion string = '2025-08-07'

var tags = {
  purpose: 'sql-ai-retrieval-lab'
  labId: labId
}

resource sql 'Microsoft.Sql/servers@2023-08-01' = {
  name: 'sqlai-${labId}-cu'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      principalType: administratorType
      login: administratorName
      sid: administratorObjectId
      tenantId: subscription().tenantId
    }
  }
}

resource desktopFirewall 'Microsoft.Sql/servers/firewallRules@2023-08-01' = {
  parent: sql
  name: 'SkillingDesktop'
  properties: {
    startIpAddress: desktopStartIpAddress
    endIpAddress: desktopEndIpAddress
  }
}

resource database 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: sql
  name: 'Healthcare'
  location: location
  tags: tags
  sku: {
    name: 'GP_S_Gen5_2'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  properties: {
    minCapacity: json('0.5')
    autoPauseDelay: 60
    maxSizeBytes: 34359738368
    requestedBackupStorageRedundancy: 'Local'
    useFreeLimit: false
  }
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: 'foundry-${labId}-cu'
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: 'foundry-${labId}-cu'
    allowProjectManagement: true
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: 'healthcare'
  location: location
  properties: {
    displayName: 'Healthcare retrieval lab'
    description: 'Dedicated synthetic-case retrieval workshop.'
  }
}

var openAiUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')

resource inferenceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundry
  name: guid(foundry.id, sql.id, openAiUserRoleId)
  properties: {
    roleDefinitionId: openAiUserRoleId
    principalId: sql.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource embedding 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: 'text-embedding-3-small'
  sku: {
    name: modelDeploymentSku
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-small'
      version: embeddingModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
  dependsOn: [project]
}

resource chat 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (includeChat) {
  parent: foundry
  name: 'gpt-5-nano'
  sku: {
    name: modelDeploymentSku
    capacity: chatCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-5-nano'
      version: chatModelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
  }
  // Account deployment updates must not run concurrently.
  dependsOn: [embedding]
}

output sqlServerFqdn string = sql.properties.fullyQualifiedDomainName
output databaseName string = database.name
output foundryAccountName string = foundry.name
output includeChat bool = includeChat
output sqlManagedIdentityObjectId string = sql.identity.principalId
