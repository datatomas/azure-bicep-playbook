#!/usr/bin/env bash
set -euo pipefail

# ===== EDIT THESE =====
RG="rg1"   # use the exact RG with hyphens
SUBSCRIPTION_NAME_OR_ID="subcritption1"  # or "" to skip

BICEP_FILE="/mnt/c/Users/SuarezTo/OneDrive - Documents/GitHub/unisys_infra_repo/iac/modules/private-endpoint-generic.bicep"
PARAMS_FILE="/mnt/c/Users/SuarezTo/OneDrive - Documents/GitHub/unisys_infra_repo/iac/params/private-endpoint-params.json"

# ===== Helpers =====
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }

need az
[[ -f "$BICEP_FILE" ]]  || { echo "ERROR: Bicep not found: $BICEP_FILE"; exit 1; }
[[ -f "$PARAMS_FILE" ]] || { echo "ERROR: Params not found: $PARAMS_FILE"; exit 1; }

# optional subscription switch
if [[ -n "$SUBSCRIPTION_NAME_OR_ID" ]]; then
  az account set --subscription "$SUBSCRIPTION_NAME_OR_ID"
fi

echo "=== What-if ==="
az deployment group what-if \
  -g "$RG" \
  -f "$BICEP_FILE" \
  -p "@$PARAMS_FILE" \
  --no-pretty-print || true

echo "=== Deploy ==="
az deployment group create \
  -g "$RG" \
  -f "$BICEP_FILE" \
  -p "@$PARAMS_FILE" \
  --query "{status:properties.provisioningState,outputs:properties.outputs}" -o yamlc

echo "=== Done ==="
