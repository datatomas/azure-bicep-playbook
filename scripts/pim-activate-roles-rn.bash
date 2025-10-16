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
# --- Load .env if exists (before defaults) ---
if [[ -f "$HOME/.env" ]]; then
  command -v dos2unix >/dev/null 2>&1 && dos2unix -q "$HOME/.env" || true
  set -a; . "$HOME/.env"; set +a
fi

# Defaults (override via env or flags)
SUB="${SUB:-addyoursubid}"
SCOPE="${SCOPE:-/subscriptions/$SUB}"                   # Overridden by --scope or --mg
MG="${MG:-addmgp}"                                         # Management group id (e.g., XM)
# Comma-separated role display names
ROLES="${ROLES:-Storage Blob Data Contributor,Owner,Azure Kubernetes Service RBAC Cluster Admin,Azure Kubernetes Service Cluster Admin Role,Key Vault Secrets Officer,Key Vault Secrets User,Key Vault Administrator}"
DURATION="${DURATION:-PT8H}"                           # ISO8601 (e.g., PT1H, PT4H, PT8H)
JUST="${JUST:-Trabajo en Ticket}"
TICKET_NO="${TICKET_NO:-}"                             # optional
TICKET_SYS="${TICKET_SYS:-}"                           # optional

# ---- flags ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sub)        SUB="$2"; SCOPE="/subscriptions/$SUB"; shift ;;
    --scope)      SCOPE="$2"; shift ;;
    --mg)         MG="$2"; shift ;;
    --roles)      ROLES="$2"; shift ;;
    --duration)   DURATION="$2"; shift ;;
    --just)       JUST="$2"; shift ;;
    --ticket-no)  TICKET_NO="$2"; shift ;;
    --ticket-sys) TICKET_SYS="$2"; shift ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac; shift
done

# If MG provided, override scope to MG
if [[ -n "${MG:-}" ]]; then
  SCOPE="/providers/Microsoft.Management/managementGroups/$MG"
fi

# ----- helpers -----
az account set --subscription "$SUB" >/dev/null

make_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then cat /proc/sys/kernel/random/uuid
  else python3 - <<'PY'
import uuid; print(uuid.uuid4())
PY
  fi
}

# Role definition id resolved at target scope
resolve_role_def_id() {
  local role_name="$1"
  local id
  id="$(az role definition list --name "$role_name" --scope "$SCOPE" --query "[0].id" -o tsv 2>/dev/null || true)"
  if [[ -z "$id" ]]; then
    echo "❌ Role not found at scope $SCOPE: $role_name" >&2
    return 1
  fi
  echo "$id"
}

principal_id() {
  az ad signed-in-user show --query id -o tsv
}

# Check if already ACTIVE (PIM assignment schedule instance exists)
has_active_instance() {
  local pid="$1" rid="$2"
  # List instances at scope and filter client-side
  local out
  if ! out="$(az rest --method GET \
        --url "https://management.azure.com$SCOPE/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01" 2>/dev/null)"; then
    return 1
  fi
  jq -e --arg pid "$pid" --arg rid "$rid" '
    .value[]?
    | select(.properties.principalId == $pid and .properties.roleDefinitionId == $rid)
    | select(.properties.status == "Provisioned" or .properties.status == "Active")
  ' >/dev/null <<<"$out"
}

# Check if there is a permanent (non-PIM) assignment at this scope
has_permanent_assignment() {
  local pid="$1" rid="$2"
  local out
  if ! out="$(az rest --method GET \
        --url "https://management.azure.com$SCOPE/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" 2>/dev/null)"; then
    return 1
  fi
  jq -e --arg pid "$pid" --arg rid "$rid" '
    .value[]?
    | select(.properties.principalId == $pid and .properties.roleDefinitionId == $rid)
  ' >/dev/null <<<"$out"
}

activate_role() {
  local role_name="$1"
  local pid rid req_id ticket_json=""
  pid="$(principal_id || true)"
  [[ -z "$pid" ]] && { echo "❌ cannot resolve signed-in principalId"; return 1; }
  rid="$(resolve_role_def_id "$role_name" || true)"
  [[ -z "$rid" ]] && { echo "❌ cannot resolve role: $role_name"; return 1; }

  # Pre-checks to avoid 400 RoleAssignmentExists
  if has_active_instance "$pid" "$rid"; then
    echo "⏩ Skip (already ACTIVE): $role_name"
    return 0
  fi
  if has_permanent_assignment "$pid" "$rid"; then
    echo "⏩ Skip (permanent assignment exists): $role_name"
    return 0
  fi

  [[ -n "$TICKET_NO" || -n "$TICKET_SYS" ]] && ticket_json=$(cat <<TJ
,"ticketInfo": {"ticketNumber":"${TICKET_NO}","ticketSystem":"${TICKET_SYS}"}
TJ
)

  echo ""
  echo "Activating: $role_name"
  echo "  Scope   : $SCOPE"
  echo "  Duration: $DURATION"
  echo "  Justif. : $JUST"

  # Do the request but DO NOT let set -e kill the loop; inspect response
  local resp rc=0
  set +e
  resp="$(az rest --only-show-errors --method PUT \
          --url "https://management.azure.com$SCOPE/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$(make_uuid)?api-version=2020-10-01" \
          --body @- <<EOF
{
  "properties": {
    "principalId": "$pid",
    "roleDefinitionId": "$rid",
    "requestType": "SelfActivate",
    "justification": "$JUST",
    "scheduleInfo": {
      "startDateTime": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
      "expiration": { "type": "AfterDuration", "duration": "$DURATION" }
    }$ticket_json
  }
}
EOF
)"; rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo "✅ Requested: $role_name"
    return 0
  fi

  # Gracefully handle "RoleAssignmentExists"
  if grep -qi 'RoleAssignmentExists' <<<"$resp"; then
    echo "⏩ Skip (already assigned by PIM): $role_name"
    return 0
  fi

  # Any other error
  echo "❌ Failed: $role_name"
  echo "$resp"
  return 1
}

# ---- run for each role (continue on errors) ----
IFS=',' read -r -a roles_arr <<< "$ROLES"
for r in "${roles_arr[@]}"; do
  role_trimmed="$(echo "$r" | sed 's/^ *//;s/ *$//')"
  [[ -z "$role_trimmed" ]] && continue
  activate_role "$role_trimmed" || { echo "⚠️  continuing…"; continue; }
done

# ---- show recent requests ----
echo ""
echo "Recent PIM requests at scope:"
az rest --method GET \
  --url "https://management.azure.com$SCOPE/providers/Microsoft.Authorization/roleAssignmentScheduleRequests?api-version=2020-10-01" \
  --query "value[0:10].{status:properties.status,role:properties.roleDefinitionId,created:properties.createdOn,just:properties.justification}" -o table || true
