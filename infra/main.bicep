targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param pineconeCanopyExists bool

@description('Id of the user or app to assign application roles')
param principalId string

// Tags that should be applied to all resources.
// 
// Note that 'azd-service-name' tags should be applied separately to service host resources.
// Example usage:
//   tags: union(tags, { 'azd-service-name': <service name in azure.yaml> })
var tags = {
  'azd-env-name': environmentName
}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))


// **** Pinecone mandatory parameters, api-key, openai-key and indexName *****
@secure()
@description('The API key for Pinecone. Used to authenticate to Pinecone services to create indexes and to insert, delete and search data. You can access your API key from the "API Keys" section in the sidebar of your dashboard')
param pineconeApiKey string
@secure()
@description('API key for OpenAI. Used to authenticate to OpenAI services for embedding and chat API. You can find your OpenAI API key in https://platform.openai.com/account/api-keys. You might need to login or register to OpenAI services')
param openAiKey string
@description('Name of the Pinecone index Canopy will underlying work with. You can choose any name as long as it follows Pinecone restrictions')
// providing a default index name based on the azd env name, subscription and location
// Allows customers to input less values and assumes the index is not created yet.
// Remove the default value if you want to force the user to input the index name.
param indexName string = 'canopy-index-${toLower(uniqueString(subscription().id, environmentName, location))}'

// **** Pinecone optional parameters, api-key, openai-key and indexName *****
@secure()
@description('Used for optional environment variables. See the read me for the list of environment variables that can be set. Use main.parameters.json to set each evnironment variable')
param pineconeCanopyDefinition object

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module monitoring './shared/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    tags: tags
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
  }
  scope: rg
}

module dashboard './shared/dashboard-web.bicep' = {
  name: 'dashboard'
  params: {
    name: '${abbrs.portalDashboards}${resourceToken}'
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    location: location
    tags: tags
  }
  scope: rg
}

module registry './shared/registry.bicep' = {
  name: 'registry'
  params: {
    location: location
    tags: tags
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
  }
  scope: rg
}

module keyVault './shared/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    tags: tags
    name: '${abbrs.keyVaultVaults}${resourceToken}'
    principalId: principalId
  }
  scope: rg
}

module appsEnv './shared/apps-env.bicep' = {
  name: 'apps-env'
  params: {
    name: '${abbrs.appManagedEnvironments}${resourceToken}'
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
  }
  scope: rg
}

module pineconeCanopy './app/pinecone-canopy.bicep' = {
  name: 'pinecone-canopy'
  params: {
    name: '${abbrs.appContainerApps}pinecone-can-${resourceToken}'
    location: location
    tags: tags
    identityName: '${abbrs.managedIdentityUserAssignedIdentities}pinecone-can-${resourceToken}'
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    containerAppsEnvironmentName: appsEnv.outputs.name
    containerRegistryName: registry.outputs.name
    exists: pineconeCanopyExists
    appDefinition: pineconeCanopyDefinition
    pineconeApiKey: pineconeApiKey
    openAiKey: openAiKey
    indexName: indexName
  }
  scope: rg
}

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.loginServer
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
