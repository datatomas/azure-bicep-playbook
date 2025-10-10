#!/usr/bin/env bash
set -euo pipefail

# Env vars (override before calling)
# SUB="${SUB:-<your-sub-id>}"
# RG="${RG:-<your-rg>}"
# PROFILE="${PROFILE:-<your-profile>}"
# ENDPOINT="${ENDPOINT:-<endpoint-name-or-host>}"

# [[ "$SUB" != "<your-sub-id>" ]] || { echo "Set SUB"; exit 1; }
# [[ "$RG" != "<your-rg>" ]] || { echo "Set RG"; exit 1; }
# [[ "$PROFILE" != "<your-profile>" ]] || { echo "Set PROFILE"; exit 1; }
# [[ "$ENDPOINT" != "<endpoint-name-or-host>" ]] || { echo "Set ENDPOINT"; exit 1; }

SUB=${SUB:-<yoursub>}
PROFILE=${PROFILE:-<yourprofile>}
ENDPOINT='cargagpe-prb'
RG=GR_FrontDoor_WAF

# --- Find RG automatically ---

az account set --subscription "$SUB"

# If ENDPOINT looks like a hostname, resolve to endpoint resource name
# --- List Rule Sets attached ONLY to routes on this endpoint ---



# Verify the endpoint exists
if ! az afd endpoint show -g "$RG" --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" >/dev/null 2>&1; then
  echo "❌ Endpoint not found: $ENDPOINT (RG=$RG, PROFILE=$PROFILE)"
  exit 1
fi

echo "== Routes on endpoint '$ENDPOINT' (with attached RuleSet IDs) =="
az afd route list -g "$RG" --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
  --query "[].{route:name,patterns:join(',',patternsToMatch),ruleSetIds:join(',', ruleSets[].id)}" -o table

# Collect unique RuleSet IDs attached to routes on this endpoint
RS_IDS=$(az afd route list -g "$RG" --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
  --query "[].ruleSets[].id" -o tsv | sort -u)

if [[ -z "$RS_IDS" ]]; then
  echo "No rule sets attached to routes on endpoint '$ENDPOINT'."
  exit 0
fi

# Build an ID->name map from the profile's rule sets
# (More reliable than splitting the ID path, avoids case issues like '/rulesets/' vs '/ruleSets/')
# Build names from IDs (case-proof) and print rules
echo
echo "== Rule details for RuleSets attached to endpoint '$ENDPOINT' =="
for RS_ID in $RS_IDS; do
  # Get the ruleset name as the last path segment (works regardless of /rulesets/ casing)
  RS_NAME="${RS_ID##*/}"
  echo "----- RuleSet: $RS_NAME ($RS_ID) -----"
  if ! az afd rule list -g "$RG" --profile-name "$PROFILE" --rule-set-name "$RS_NAME" \
        --query "[].{name:name,order:order,match:matchConditions,actions:actions}" -o jsonc; then
    echo "⚠️  Could not fetch rules for RuleSet name '$RS_NAME'."
  fi
done



# =======================
# Error handling summary
# =======================

echo
echo "== Error handling summary for endpoint '$ENDPOINT' =="

# 1) Per-route summary of rewrite destinations and 404 matching (from attached rule sets)
#    (We scan only the rule sets attached to THIS endpoint's routes)
ROUTES_TSV=$(az afd route list -g "$RG" --profile-name "$PROFILE" --endpoint-name "$ENDPOINT" \
  --query "[].{route:name,ruleSetIds:join(',', ruleSets[].id)}" -o tsv)

if [[ -z "$ROUTES_TSV" ]]; then
  echo "No routes found on endpoint '$ENDPOINT'."
else
  while IFS=$'\t' read -r ROUTE RSIDS; do
    echo "---- Route: $ROUTE ----"
    IFS=',' read -ra IDS <<< "$RSIDS"
    for RS_ID in "${IDS[@]}"; do
      [[ -z "$RS_ID" ]] && continue
      RS_NAME="${RS_ID##*/}"
      echo "  RuleSet: $RS_NAME"
      # Show rules that perform UrlRewrite (destinations), and flag if they match 404 responses
    az afd rule list -g "$RG" --profile-name "$PROFILE" --rule-set-name "$RS_NAME" \
    --only-show-errors \
    --query "[].{
        name: name,
        order: order,
        rewrites: join(',', actions[?name=='UrlRewrite'].parameters.destination),
        redirects: join(',', actions[?name=='UrlRedirect'].parameters.destination)
    }" -o table

    done
  done <<< "$ROUTES_TSV"
fi

# 2) (Optional) Print Storage Static Website error document if SA is provided
if [[ -n "${SA:-}" ]]; then
  echo
  echo "== Storage static website settings (account: $SA) =="
  az storage blob service-properties show --auth-mode login --account-name "$SA" \
    --query "{enabled:staticWebsite.enabled,index:staticWebsite.indexDocument,error:staticWebsite.errorDocument404Path}" -o table 2>/dev/null || \
    echo "  ⚠️ Could not read static website settings for $SA (missing rights or not enabled)."
fi
