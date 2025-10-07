#!/usr/bin/env bash
set -euo pipefail

# ==== CONFIG ====
RG="rg1"
LOC="subcription1"
# AZ_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"   # optional

# Paths (Windows → WSL)
BICEP_FILE="/mnt/c/Users/SuarezTo/OneDrive - Unisys/Documents/GitHub/unisys_infra_repo/iac/modules/document-intelligence-entra-system.bicep"
PARAMS_FILE="/mnt/c/Users/SuarezTo/OneDrive - Unisys/Documents/GitHub/unisys_infra_repo/iac/params/document-intelligence-params.json"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1"; exit 1; }; }

ensure_rg_tags_from_params() {
  echo ">> Reading RG tags from: $PARAMS_FILE"
  # Prefer parameters.rgTags.value; fallback to parameters.tags.value
  local tags_json
  tags_json="$(jq -c '
      if (.parameters.rgTags.value? != null) then
        .parameters.rgTags.value
      else
        .parameters.tags.value
      end
    ' "$PARAMS_FILE")"

  if [[ -z "$tags_json" || "$tags_json" == "null" ]]; then
    echo "ERROR: could not read tags from params file (expected .parameters.rgTags.value or .parameters.tags.value)."
    exit 1
  fi

  echo ">> Applying tags to RG $RG"
  # Pass the whole JSON object; az will replace the tag set with this object.
  az group update --name "$RG" --set tags="$tags_json" >/dev/null
}

# ==== MAIN ====
need az
need jq

[[ -f "$BICEP_FILE" ]]  || { echo "ERROR: Bicep not found: $BICEP_FILE"; exit 1; }
[[ -f "$PARAMS_FILE" ]] || { echo "ERROR: Params not found: $PARAMS_FILE"; exit 1; }

if [[ -n "${AZ_SUBSCRIPTION_ID:-}" ]]; then
  az account set --subscription "$AZ_SUBSCRIPTION_ID"
fi

echo "=== Step 1/3: Update RG tags from params (policy) ==="
ensure_rg_tags_from_params

echo "=== Step 2/3: What-if ==="
az deployment group what-if \
  -g "$RG" \
  -f "$BICEP_FILE" \
  -p "@$PARAMS_FILE" \
  --no-pretty-print || true

echo "=== Step 3/3: Deploy ==="
az deployment group create \
  -g "$RG" \
  -f "$BICEP_FILE" \
  -p "@$PARAMS_FILE" \
  --query "{status:properties.provisioningState,outputs:properties.outputs}" -o yamlc

echo "=== DONE ==="
