#!/usr/bin/env bash
set -euo pipefail

# =====================================
# Auto-detect RG for an AFD profile and list its endpoints
# =====================================

SUB=${SUB:-<yoursub>}
PROFILE=${PROFILE:-<yourprofile>}
ENDPOINT='cargagpe-prb'

az account set --subscription "$SUB"

# --- Find RG automatically ---
RG=GR_FrontDoor_WAF

if [[ -z "$RG" ]]; then
  echo "❌ Could not find AFD profile '$PROFILE' in subscription $SUB" >&2
  exit 1
fi

echo "✅ Found AFD profile '$PROFILE' in resource group '$RG'"
echo
az resource show \
  --ids "/subscriptions/"$SUB"/resourceGroups/"$RG"/providers/Microsoft.Cdn/profiles/"$Profile" \
  -o jsonc
  
# --- List endpoints for the profile ---
az afd endpoint list \
  -g "$RG" \
  --profile-name "$PROFILE" \
  --subscription "$SUB" \
  --query "[].{name:name, host:hostName, state:provisioningState, enabled:enabledState}" \
  -o table


az afd route list \
  -g "$RG" \
  --profile-name "$PROFILE" \
  --endpoint-name "$PROFILE" \
  --subscription "$SUB" \
  --query "[].{name:name, patterns:join(',',patternsToMatch), originGroup:originGroup.id, enabled:enabledState, httpsRedirect:httpsRedirect, caching:cachingConfiguration.cacheBehavior}" \
  -o table
