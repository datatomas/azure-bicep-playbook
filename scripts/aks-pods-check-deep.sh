#!/usr/bin/env bash
set -euo pipefail

# Usage: ./pod-info.sh <pod-name> [namespace]
POD=yourpodname
# --- tools ---
#!/usr/bin/env bash

command -v kubectl >/dev/null || { echo "kubectl not found"; exit 1; }

# Args & env

NS="${2:-${NS:-}}"

if [[ -z "${POD}" ]]; then
  echo "Usage: $0 <pod-name-or-prefix> [namespace]"
  exit 2
fi

# Resolve namespace if not provided (exact name first, then prefix)
if [[ -z "${NS:-}" ]]; then
  NS="$(kubectl get pod -A --field-selector=metadata.name="${POD}" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)"
  if [[ -z "$NS" ]]; then
    NS="$(kubectl get pods -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name' --no-headers \
        | awk -v p="^${POD}" '$2 ~ p { print $1; exit }')"
  fi
  [[ -z "$NS" ]] && { echo "❌ Could not find a namespace for pod/prefix '${POD}'"; exit 3; }
fi

# Resolve actual pod name (accept prefix)
if ! kubectl -n "$NS" get pod "$POD" -o name >/dev/null 2>&1; then
  RESOLVED="$(kubectl -n "$NS" get pods --sort-by=.metadata.creationTimestamp -o custom-columns=':metadata.name' --no-headers \
      | awk -v p="^${POD}" '$0 ~ p { last=$0 } END { print last }')"
  [[ -z "$RESOLVED" ]] && { echo "❌ Pod '${POD}' not found in ns '${NS}'"; exit 4; }
  POD="$RESOLVED"
fi

# --- basic facts ---
NODE="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.spec.nodeName}')"
IMAGES="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].image}')"
PHASE="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.phase}')"
RESTARTS="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[*].restartCount}')"
TERM_REASON="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[*].lastState.terminated.reason}')"
TERM_CODE="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.status.containerStatuses[*].lastState.terminated.exitCode}')"

# --- owner chain ---
RS="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="ReplicaSet")].name}')"
OWNER_KIND="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.metadata.ownerReferences[0].kind}')"
OWNER_NAME="$(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.metadata.ownerReferences[0].name}')"
DEP=""
if [[ -n "$RS" ]]; then
  DEP="$(kubectl -n "$NS" get rs "$RS" -o jsonpath='{.metadata.ownerReferences[?(@.kind=="Deployment")].name}' 2>/dev/null || true)"
fi

echo "────────────────────────────────────────────────────────"
echo "Pod:           $POD"
echo "Namespace:     $NS"
echo "Node:          $NODE"
echo "Images:        $IMAGES"
echo "Phase:         $PHASE"
echo "Restarts:      ${RESTARTS:-0}"
echo "Last reason:   ${TERM_REASON:-N/A}  (exit ${TERM_CODE:-N/A})"
if [[ -n "$DEP" ]]; then
  echo "Owned by:      Deployment/$DEP  (via ReplicaSet/$RS)"
else
  echo "Owned by:      ${OWNER_KIND:-N/A}/${OWNER_NAME:-N/A}"
  [[ -n "$RS" ]] && echo "ReplicaSet:    $RS (no Deployment owner found)"
fi
echo "────────────────────────────────────────────────────────"
kubectl -n "$NS" get pod "$POD" -o wide
echo "────────────────────────────────────────────────────────"
echo "Describe (containers section):"
kubectl -n "$NS" describe pod "$POD" | sed -n '/Containers:/,$p'
echo "────────────────────────────────────────────────────────"
echo "Last-failure logs (if container restarted):"
mapfile -t CONTAINERS < <(kubectl -n "$NS" get pod "$POD" -o jsonpath='{.spec.containers[*].name}' | tr ' ' '\n')
for C in "${CONTAINERS[@]}"; do
  echo "---- container: $C (previous) ----"
  if kubectl -n "$NS" logs "$POD" -c "$C" --previous --tail=500 >/dev/null 2>&1; then
    kubectl -n "$NS" logs "$POD" -c "$C" --previous --tail=500
  else
    echo "(no previous logs; showing current tail)"
    kubectl -n "$NS" logs "$POD" -c "$C" --tail=200 || true
  fi
done
