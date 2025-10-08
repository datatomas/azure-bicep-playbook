@description('Name of the Private Endpoint')
param privateEndpointName string

@description('Deployment location (use same region as target resource or VNet)')
param location string = resourceGroup().location

@description('Subnet Resource ID where the PE NIC will be created')
param subnetId string

@description('Resource ID of the target resource (e.g., Key Vault, Storage Account, Cognitive Services, etc.)')
param targetResourceId string

@description('Group IDs for the Private Link connection (depends on the resource type, e.g., "vault", "blob", "file", "account")')
param groupIds array

@description('Private Endpoint connection name')
param connectionName string

@description('Whether to create the DNS Zone Group (default = true)')
param enableDnsLink bool = true

@description('Name of the Private DNS Zone Group (child resource under the Private Endpoint)')
param dnsZoneGroupName string = 'default'

@description('Private DNS Zone resource ID (existing zone, possibly cross-subscription)')
param dnsZoneId string = ''

@description('Optional custom request message shown in the private link request')
param requestMessage string = 'Private Endpoint connection requested via automation'

@description('Tags to apply to the Private Endpoint')
param tags object = {}

@description('Manual approval flag (set to true for resources requiring manual connection approval)')
param manualApproval bool = false


// === Main Private Endpoint ===
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    manualPrivateLinkServiceConnections: manualApproval
      ? [
          {
            name: connectionName
            properties: {
              privateLinkServiceId: targetResourceId
              groupIds: groupIds
              requestMessage: requestMessage
            }
          }
        ]
      : []
    privateLinkServiceConnections: manualApproval
      ? []
      : [
          {
            name: connectionName
            properties: {
              privateLinkServiceId: targetResourceId
              groupIds: groupIds
              requestMessage: requestMessage
            }
          }
        ]
  }
}

// === Optional DNS Zone Group (only if linking requested) ===
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (enableDnsLink && !empty(dnsZoneId)) {
  name: dnsZoneGroupName
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'default'
        properties: {
          privateDnsZoneId: dnsZoneId
        }
      }
    ]
  }
}

output privateEndpointId string = privateEndpoint.id
output privateEndpointNicId string = privateEndpoint.properties.networkInterfaces[0].id
