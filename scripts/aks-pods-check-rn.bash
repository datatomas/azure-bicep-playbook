#!/usr/bin/env bash
set -euo pipefail

# --- Load env for non-interactive shells ---
if [[ -f "$HOME/.env" ]]; then
  command -v dos2unix >/dev/null 2>&1 && dos2unix -q "$HOME/.env" || true
  set -a; . "$HOME/.env"; set +a
else
  echo "ERROR: ~/.env not found" >&2; exit 1
fi

# Required (unset or empty ⇒ exit with the given message)
: "${SUB:?Set SUB in ~/.env (subscription id or name)}"
: "${RG:?Set RG in ~/.env (resource group)}"
: "${CLUSTER:?Set CLUSTER in ~/.env (AKS cluster name)}"
: "${SUDO_PASS:?Set SUDO_PASS in ~/.env (for install step)}"
: "${NS:?Set NS in ~/.env (k8s namespace, e.g. default)}"
: "${REGION:?Set REGION in ~/.env (e.g. brazilsouth)}"


# Helper to run sudo with password from env (scoped use only)
sudo_pw() {
  printf '%s\n' "$SUDO_PASS" | sudo -S "$@"
}

# Validate sudo once (caches credential timestamp)
printf '%s\n' "$SUDO_PASS" | sudo -S -v

# --- Install kubectl/kubelogin system-wide (needs sudo) ---
need_install=false
command -v kubectl >/dev/null 2>&1 || need_install=true
command -v kubelogin >/dev/null 2>&1 || need_install=true

if [[ "$need_install" == true ]]; then
  echo "Installing kubectl and kubelogin into /usr/local/bin ..."
  sudo_pw az aks install-cli \
    --install-location /usr/local/bin/kubectl \
    --kubelogin-install-location /usr/local/bin/kubelogin
  sudo_pw chmod +x /usr/local/bin/kubectl /usr/local/bin/kubelogin
fi

# --- Azure auth (do NOT use sudo here) ---
# If you're already logged in, this won't prompt; else, login before running the script.
az account show >/dev/null 2>&1 || {
  echo "Not logged in. Run: az login --use-device-code"; exit 1;
}
az account set --subscription "$SUB"

echo "Kubernetes cluster version:"
az aks show -g "$RG" -n "$CLUSTER" --query "kubernetesVersion" -o tsv

# --- AKS context & kubelogin conversion ---
az aks get-credentials -g "$RG" -n "$CLUSTER" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

# --- Print kubelet identity (as requested) ---
echo "Kubelet identity resourceId:"
az aks show \
  --resource-group "$RG" \
  --name "$CLUSTER" \
  --query "identityProfile.kubeletidentity.resourceId" \
  -o tsv

#Node pools
az aks nodepool list -g "$RG" --cluster-name "$CLUSTER" \
  --query "[].{name:name,mode:mode,os:osType,version:orchestratorVersion}" -o table

#Versions lists
#check available updates
az aks get-upgrades --resource-group "$RG" --name "$CLUSTER" --output table
 
#check available updates per region
az aks get-versions --location eastus2 --output table
#minor graduales 1.2 no import 1.2.3


# --- Smoke tests ---
kubectl version --client 
kubectl get pods -n "$NS"
