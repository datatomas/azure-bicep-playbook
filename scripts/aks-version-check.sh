#!/usr/bin/env bash
set -euo pipefail

# Load env
if [[ -f "$HOME/.env" ]]; then
  command -v dos2unix >/dev/null 2>&1 && dos2unix -q "$HOME/.env" || true
  set -a; . "$HOME/.env"; set +a
fi

: "${SUB:?Set SUB}"
RG="${RG:-${RG:-}}"; : "${RG:?Set RG or RG}"
: "${CLUSTER:?Set CLUSTER (e.g. aks-qwe-prd01)}"
POOL="${POOL:-}"  # optional now

az account set --subscription "$SUB"

echo "== Cluster =="
az aks show -g "$RG" -n "$CLUSTER" \
  --query "{version:kubernetesVersion,region:location,channel:autoUpgradeProfile.upgradeChannel}" -o table

echo -e "\n== Offered Upgrades =="
az aks get-upgrades -g "$RG" -n "$CLUSTER" -o table

echo -e "\n== Node Pools =="
az aks nodepool list -g "$RG" --cluster-name "$CLUSTER" \
  --query "[].{name:name,mode:mode,version:orchestratorVersion,nodeImage:nodeImageVersion,maxSurge:upgradeSettings.maxSurge}" -o table


REGION="${REGION:-$(az aks show -g "$RG" -n "$CLUSTER" --query location -o tsv)}"
echo -e "\n== Versions in $REGION =="
az aks get-versions --location "$REGION" -o table

echo -e "\n== Node kubelet versions by pool =="
kubectl get nodes -L agentpool -o custom-columns=NAME:.metadata.name,POOL:.metadata.labels.agentpool,VERSION:.status.nodeInfo.kubeletVersion

echo -e "\n== Recent events (cluster-wide) =="
kubectl get events --sort-by=.lastTimestamp | tail -n 50

#echo
#confirm update
echo -e "\n== Was the update succesful =="

az aks show -g $RG -n $CLUSTER --query "{version:kubernetesVersion, state:provisioningState}" -o json

if [[ -n "$POOL" ]]; then
  echo -e "\n== Selected Pool ($POOL) Settings =="
  az aks nodepool show -g "$RG" --cluster-name "$CLUSTER" -n "$POOL" \
    --query "{name:name,version:orchestratorVersion,nodeImage:nodeImageVersion,upgradeSettings:upgradeSettings}" -o jsonc
fi
