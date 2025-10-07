@description('Nombre de la cuenta de Azure Document Intelligence (debe ser único si se usa como customSubDomainName).')
param name string

@description('Ubicación. Por defecto usa la del Resource Group.')
param location string = resourceGroup().location

@description('SKU del servicio')
@allowed([
  'S0'
  'PayAsYouGo'
])
param skuName string = 'S0'

@description('Custom subdomain (sin puntos). Forma https://<subdomain>.cognitiveservices.azure.com')
param customSubdomainName string

@description('Tags a aplicar al recurso.')
param tags object = {}

resource docint 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: name
  location: location
  kind: 'FormRecognizer'
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Requisitos de tu baseline de seguridad
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true

    // Si este nombre ya existe globalmente, el despliegue fallará.
    // En ese caso, quita o cambia este valor y vuelve a desplegar.
    customSubDomainName: customSubdomainName
  }
  tags: tags
}

output endpoint string = 'https://${customSubdomainName}.cognitiveservices.azure.com'
output accountId string = docint.id
