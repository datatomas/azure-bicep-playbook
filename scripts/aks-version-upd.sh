#!/usr/bin/env bash
set -euo pipefail

# =====================================
# AKS UPGRADE RUNNER (Explicit version only)
# =====================================
# Requires: az CLI + authenticated session (az login)
# Reads (env or exported beforehand):
#   SUB              -> subscription id or name
#   RG   -> RG name, or fallback to RG
#   CLUSTER     -> AKS cluster name
#   NEW_VERSION      -> target version (must be explicitly set)
# Optional:
#   RG               -> legacy/alternate variable for RG name
# =====================================

# --- Load env file if exists (WSL-safe) ---
if [[ -f "$HOME/.env" ]]; then
  command -v dos2unix >/dev/null 2>&1 && dos2unix -q "$HOME/.env" || true
  set -a; . "$HOME/.env"; set +a
fi

# --- Read / normalize inputs ---
SUB="${SUB:?Set SUB in ~/.env or env (subscription id or name)}"
RG="${RG:-${RG:-}}"
: "${RG:?Set RG or RG (e.g. GR_MDC_PRB)}"
: "${CLUSTER:?Set CLUSTER (e.g. aks-mdc-prb-01)}"
: "${NEW_VERSION:?Set NEW_VERSION manually (e.g. 1.minor.6)}"

echo "==============================="
echo " AKS Upgrade Runner"
echo "==============================="
echo "Subscription   : $SUB"
echo "Resource Group : $RG"
echo "Cluster Name   : $CLUSTER"
echo "Target Version : $NEW_VERSION"
echo

# --- Ensure az + login ---
if ! command -v az >/dev/null 2>&1; then
  echo "❌ Azure CLI (az) not found"; exit 1
fi
if ! az account show >/dev/null 2>&1; then
  echo "⚠️ Not logged in to Azure. Run: az login --use-device-code"
  exit 1
fi

# --- Set subscription explicitly from SUB ---
echo "🔐 Setting subscription..."
az account set --subscription "$SUB"
echo "✅ Active subscription:"
az account show --query "{name:name, id:id, tenantId:tenantId}" -o table
echo

# --- Get current version ---
CURRENT_VERSION=$(az aks show -g "$RG" -n "$CLUSTER" --query "kubernetesVersion" -o tsv)
echo "Current version : $CURRENT_VERSION"

if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
  echo "✅ Cluster is already at version $NEW_VERSION"
  exit 0
fi

# --- Check if target version is available ---
AVAILABLE=$(
  az aks get-upgrades -g "$RG" -n "$CLUSTER" \
    --query "controlPlaneProfile.upgrades[].kubernetesVersion" -o tsv \
  | grep -Fx "$NEW_VERSION" || true
)
if [[ -z "$AVAILABLE" ]]; then
  echo "❌ Version $NEW_VERSION not available for upgrade. Show available with:"
  echo "   az aks get-upgrades -g \"$RG\" -n \"$CLUSTER\" -o table"
  exit 1
fi

# --- Confirm + upgrade control plane ---
echo
echo "🚀 Upgrading cluster $CLUSTER in $RG to $NEW_VERSION..."
az aks upgrade \
  --resource-group "$RG" \
  --name "$CLUSTER" \
  --kubernetes-version "$NEW_VERSION" \
  --yes

# --- Verify post-upgrade ---
echo
echo "🔍 Verifying cluster upgrade..."
az aks show -g "$RG" -n "$CLUSTER" \
  --query "{name:name, kubernetesVersion:kubernetesVersion, provisioningState:provisioningState}" -o table

echo
echo "✅ Upgrade completed successfully."
