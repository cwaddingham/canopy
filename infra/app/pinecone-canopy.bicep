param name string
param location string = resourceGroup().location
param tags object = {}

param identityName string
param containerRegistryName string
param containerAppsEnvironmentName string
param applicationInsightsName string
param exists bool

@secure()
param appDefinition object

@secure()
@description('The API key for Pinecone. Used to authenticate to Pinecone services to create indexes and to insert, delete and search data. You can access your API key from the "API Keys" section in the sidebar of your dashboard')
param pineconeApiKey string
@secure()
@description('API key for OpenAI. Used to authenticate to OpenAI services for embedding and chat API. You can find your OpenAI API key in https://platform.openai.com/account/api-keys. You might need to login or register to OpenAI services')
param openAiKey string
@description('Name of the Pinecone index Canopy will underlying work with. You can choose any name as long as it follows Pinecone restrictions')
param indexName string

// Generate secrets and env from appDefinition
var appSettingsArray = filter(array(appDefinition.settings), i => i.name != '')
var generatedSecrets = map(filter(appSettingsArray, i => i.?secret != null), i => {
  name: i.name
  value: i.value
  secretRef: i.?secretRef ?? take(replace(replace(toLower(i.name), '_', '-'), '.', '-'), 32)
})
var generatedEnv = map(filter(appSettingsArray, i => i.?secret == null), i => {
  name: i.name
  value: i.value
})

// Add mandatory settings to secrets and env
var secrets = union(generatedSecrets, [
  {
    name: 'pinecone-api-key'
    value: pineconeApiKey
    secretRef: 'pinecone-api-key'
  }
  {
    name: 'open-ai-key'
    value: openAiKey
    secretRef: 'open-ai-key'
  }
])

var env = union(generatedEnv, [
  {
    name: 'PINECONE_API_KEY'
    secretRef: 'pinecone-api-key'
  }
  {
    name: 'OPENAI_API_KEY'
    secretRef: 'open-ai-key'
  }
  {
    name: 'INDEX_NAME'
    value: indexName
  }
])

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: containerRegistryName
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: containerAppsEnvironmentName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(subscription().id, resourceGroup().id, identity.id, 'acrPullRole')
  properties: {
    roleDefinitionId:  subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalType: 'ServicePrincipal'
    principalId: identity.properties.principalId
  }
}

module fetchLatestImage '../modules/fetch-container-image.bicep' = {
  name: '${name}-fetch-image'
  params: {
    exists: exists
    name: name
  }
}

resource app 'Microsoft.App/containerApps@2023-05-02-preview' = {
  name: name
  location: location
  tags: union(tags, {'azd-service-name':  'pinecone-canopy' })
  dependsOn: [ acrPullRole ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress:  {
        external: true
        targetPort: 8000
        transport: 'auto'
      }
      registries: [
        {
          server: '${containerRegistryName}.azurecr.io'
          identity: identity.id
        }
      ]
      secrets: union([
      ],
      map(secrets, secret => {
        name: secret.secretRef
        value: secret.value
      }))
    }
    template: {
      containers: [
        {
          image: fetchLatestImage.outputs.?containers[?0].?image ?? 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          name: 'main'
          env: union([
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsights.properties.ConnectionString
            }
            {
              name: 'PORT'
              value: '8000'
            }
          ],
          env,
          map(secrets, secret => {
            name: secret.name
            secretRef: secret.secretRef
          }))
          resources: {
            cpu: json('1.0')
            memory: '2.0Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}

output defaultDomain string = containerAppsEnvironment.properties.defaultDomain
output name string = app.name
output uri string = 'https://${app.properties.configuration.ingress.fqdn}'
output id string = app.id
