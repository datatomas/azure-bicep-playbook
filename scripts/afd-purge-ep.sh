#!/usr/bin/env bash
# --- Purge AFD endpoint content ---

: "${AFD_PROFILE:?Set AFD_PROFILE in ~/.env}"
: "${AFD_ENDPOINT:?Set AFD_ENDPOINT in ~/.env}"
: "${RG:?Set RG in ~/.env}"
: "${SUB:?Set SUB in ~/.env}"

echo "🚀 Purging endpoint '${AFD_ENDPOINT}' on profile '${AFD_PROFILE}' (RG=${RG}, SUB=${SUB})"

# Optional sanity check (fail fast if names are wrong)
az afd endpoint show \
  --resource-group "$RG" \
  --profile-name   "$AFD_PROFILE" \
  --endpoint-name  "$AFD_ENDPOINT" \
  --subscription   "$SUB" \
  -o none

# Purge everything (keep the single quotes so the shell doesn't expand the *)
az afd endpoint purge \
  --resource-group "$RG" \
  --profile-name   "$AFD_PROFILE" \
  --endpoint-name  "$AFD_ENDPOINT" \
  --content-paths  '/*' \
  --subscription   "$SUB"

echo "✅ Purge request submitted."
