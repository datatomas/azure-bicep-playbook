#!/usr/bin/env bash
set -euo pipefail

# ==============================
# PIM activate multiple RBAC roles (SelfActivate)
# Supports scopes:
#   - Subscription:           /subscriptions/<subId>
#   - Resource Group:         /subscriptions/<subId>/resourceGroups/<rg>
#   - Resource:               (full Azure resource ID)
#   - Management Group (MG):  /providers/Microsoft.Management/managementGroups/<mgId>
# ==============================

# Defaults (override via env or flags)
SUB="${SUB:-<SUBID>}"
SCOPE="${SCOPE:-/subscriptions/$SUB}"       # Overridden by --scope or --mg
MG="${MG:-<YOURMANAGEMENTGROUP>}"                              # Management group id (e.g., XM). Set empty to use SUB scope.
# Comma-separated list of role display names
ROLES="${ROLES:-Storage Blob Data Contributor,Owner,Azure Kubernetes Service RBAC Cluster Admin,Azure Kubernetes Service Contributor Role,Key Vault Secrets Officer,Key Vault Secrets User,Key Vault Administrator}"
DURATION="${DURATION:-PT8H}"                # ISO8601 (PT1H/PT4H/PT8H)
JUST="${JUST:-Operational need}"
TICKET_NO="${TICKET_NO:-}"                  # optional
TICKET_SYS="${TICKET_SYS:-}"                # optional

# ---- flags ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sub)        SUB="$2"; SCOPE="/subscriptions/$SUB"; shift ;;
    --scope)      SCOPE="$2"; shift ;;                       # full scope id
    --mg)         MG="$2"; shift ;;                          # management group id
    --roles)      ROLES="$2"; shift ;;
    --duration)   DURATION="$2"; shift ;;
    --just)       JUST="$2"; shift ;;
    --ticket-no)  TICKET_NO="$2"; shift ;;
    --ticket-sys) TICKET_SYS="$2"; shift ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac; shift
done

# If MG provided (non-empty), override scope to MG
if [[ -n "${MG:-}" ]]; then
  SCOPE="/providers/Microsoft.Management/managementGroups/$MG"
fi

az account set --subscription "$SUB"

# ---- helpers ----
make_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then cat /proc/sys/kernel/random/uuid
  else python3 - <<'PY'
import uuid; print(uuid.uuid4())
PY
  fi
}

# Resolve roleDefinitionId for a role name at the given SCOPE.
resolve_role_def_id() {
  local role_name="$1" id
  id="$(az role definition list --name "$role_name" --scope "$SCOPE" --query "[0].id" -o tsv || true)"
  if [[ -z "$id" ]]; then
    echo "❌ Role not found at scope $SCOPE: $role_name" >&2
    return 1
  fi
  echo "$id"
}

# Check ACTIVE (Provisioned) PIM assignment for this principal+role at this scope.
has_active_pim_assignment() {
  local principal_id="$1" role_def_id="$2"
  local url q count
  url="https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01"
  q="[?properties.principalId=='${principal_id}' && properties.roleDefinitionId=='${role_def_id}' && properties.status=='Provisioned'] | length(@)"
  count="$(az rest --only-show-errors --method GET --url "$url" --query "$q" -o tsv 2>/dev/null || echo 0)"
  [[ "${count:-0}" -gt 0 ]]
}

# Check PERMANENT (non-PIM) role assignment.
has_persistent_assignment() {
  local principal_id="$1" role_def_id="$2"
  local url q count
  url="https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"
  q="[?properties.principalId=='${principal_id}' && properties.roleDefinitionId=='${role_def_id}'] | length(@)"
  count="$(az rest --only-show-errors --method GET --url "$url" --query "$q" -o tsv 2>/dev/null || echo 0)"
  [[ "${count:-0}" -gt 0 ]]
}

activate_role() {
  local role_name="$1"
  local principal_id role_def_id req_id ticket_json=""

  principal_id="$(az ad signed-in-user show --query id -o tsv)"
  role_def_id="$(resolve_role_def_id "$role_name")" || { echo "Skip (role not found): $role_name"; return 0; }

  # Pre-checks: skip if already active (PIM) or permanent
  if has_active_pim_assignment "$principal_id" "$role_def_id"; then
    echo ""
    echo "Skipping: $role_name (already active via PIM at $SCOPE)"
    return 0
  fi
  if has_persistent_assignment "$principal_id" "$role_def_id"; then
    echo ""
    echo "Skipping: $role_name (permanent assignment exists at $SCOPE)"
    return 0
  fi

  req_id="$(make_uuid)"

  [[ -n "$TICKET_NO" || -n "$TICKET_SYS" ]] && ticket_json=$(cat <<TJ
,"ticketInfo": {"ticketNumber":"${TICKET_NO}","ticketSystem":"${TICKET_SYS}"}
TJ
)

  echo ""
  echo "Activating: $role_name"
  echo "  Scope   : $SCOPE"
  echo "  Duration: $DURATION"
  echo "  Justif. : $JUST"

  # Capture both stdout+stderr to detect RoleAssignmentExists reliably
  set +e
  resp="$(az rest --only-show-errors --method PUT \
    --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/${req_id}?api-version=2020-10-01" \
    --body @- 2>&1 <<EOF
{
  "properties": {
    "principalId": "$principal_id",
    "roleDefinitionId": "$role_def_id",
    "requestType": "SelfActivate",
    "justification": "$JUST",
    "scheduleInfo": {
      "startDateTime": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
      "expiration": { "type": "AfterDuration", "duration": "$DURATION" }
    }$ticket_json
  }
}
EOF
)"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    if echo "$resp" | grep -qi 'RoleAssignmentExists'; then
      echo "Already active: $role_name (server reported RoleAssignmentExists) — continuing."
      return 0
    fi
    echo "❌ Activation failed for $role_name"
    echo "$resp"
    # Return non-zero but let caller decide to continue
    return 1
  fi

  # Success path
  echo "$resp"
  return 0
}

# ---- run for each role; never abort whole script on one failure ----
IFS=',' read -r -a roles_arr <<< "$ROLES"
for r in "${roles_arr[@]}"; do
  role_trimmed="$(echo "$r" | sed 's/^ *//;s/ *$//')"
  [[ -z "$role_trimmed" ]] && continue
  if ! activate_role "$role_trimmed"; then
    echo "⚠️  Continuing after error on role: $role_trimmed"
  fi
done

# ---- show recent requests ----
echo ""
echo "Recent PIM requests at scope:"
az rest --only-show-errors --method GET \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleAssignmentScheduleRequests?api-version=2020-10-01" \
  --query "value[0:10].{status:properties.status,role:properties.roleDefinitionId,created:properties.createdOn,just:properties.justification}" -o table
