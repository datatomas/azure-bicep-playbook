#!/bin/bash

# Set variables
SUBSCRIPTION_ID="subthatholdstheresource"
RG="rgthatholdstheresource"
USER_EMAIL="toberemoveduser"  # Replace with actual user email
RESOURCE_NAME="resourcename"     # Replace with actual Key Vault name
RESOURCE_TYPE="Microsoft.DataFactory" #Repalce with each resource type
# Set the subscription
az account set --subscription "$SUBSCRIPTION_ID"

# Get the object ID of the user from Azure AD
USER_OBJID=$(az ad user list \
  --filter "userPrincipalName eq '$USER_EMAIL'" \
  --query "[0].id" -o tsv)

if [ -z "$USER_OBJID" ]; then
  echo "Error: User with email $USER_EMAIL not found in Azure AD."
  exit 1
fi

# Construct Key Vault resource ID
KV_ID="/subscriptions/"$SUBSCRIPTION_ID"/resourceGroups/${RG}/providers/"$RESOURCE_TYPE"/vaults/${RESOURCE_NAME}"

# List current role assignments
echo "Current role assignments for user $USER_EMAIL ($USER_OBJID) on Key Vault:"
az role assignment list \
  --scope "$KV_ID" \
  --assignee "$USER_OBJID" \
  --query "[].{id:id, role:roleDefinitionName}" -o table

# Remove all role assignments
echo "Removing all role assignments..."
for ID in $(az role assignment list --scope "$KV_ID" --assignee "$USER_OBJID" --query [].id -o tsv); do
  echo "Deleting role assignment ID: $ID"
  az role assignment delete --ids "$ID"
done

echo "All RBAC roles removed for $USER_EMAIL on Key Vault: $RESOURCE_NAME"
