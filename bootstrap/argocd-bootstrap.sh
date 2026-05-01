#!/usr/bin/env bash
# =============================================================================
# bootstrap/argocd-bootstrap.sh
#
# Bootstrap ArgoCD nel cluster lcn-lab (Fase 2).
# Operazione una-tantum: installa ArgoCD dal manifest versionato in repo
# e registra le credenziali del repo GitHub per il flusso GitOps.
#
# PREREQUISITI
#   - Cluster lcn-lab attivo  (kubectl config current-context = k3d-lcn-lab)
#   - kubectl nel PATH
#
# USO
#   ./bootstrap/argocd-bootstrap.sh
#
# Il parametro ARGOCD_REPO_SECRET (opzionale) permette di passare un token
# GitHub per registrare il repo privato. Se omesso, la root Application
# non viene applicata e le istruzioni vengono stampate a video.
#
# Variabili d'ambiente opzionali:
#   GH_TOKEN   — Personal Access Token GitHub (scope: repo)
#   REPO_URL   — URL HTTPS del repo (default: github.com/afiorillo68/localcloudnative-lab)
# =============================================================================
set -euo pipefail

ARGOCD_VERSION="v2.13.3"          # deve corrispondere a platform/argocd/install.yaml
ARGOCD_NAMESPACE="argocd"
REPO_URL="${REPO_URL:-https://github.com/afiorillo68/localcloudnative-lab}"
GH_TOKEN="${GH_TOKEN:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Colori
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR]${NC}   $*" >&2; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "none")
if [[ "${CURRENT_CTX}" != "k3d-lcn-lab" ]]; then
  error "Context attuale: '${CURRENT_CTX}'. Atteso: 'k3d-lcn-lab'."
  error "Esegui: kubectl config use-context k3d-lcn-lab"
  exit 1
fi
info "Context kubectl: ${CURRENT_CTX} — OK"

if [[ ! -f "${REPO_ROOT}/platform/argocd/install.yaml" ]]; then
  error "platform/argocd/install.yaml non trovato."
  error "Assicurati di eseguire lo script dalla root del repo clonato."
  exit 1
fi
info "Manifest ArgoCD ${ARGOCD_VERSION} trovato in platform/argocd/ — OK"

# ---------------------------------------------------------------------------
# 1. Namespace argocd
# ---------------------------------------------------------------------------
info "Creo namespace ${ARGOCD_NAMESPACE} (idempotente)..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml \
  | kubectl apply -f -

# ---------------------------------------------------------------------------
# 2. Installa ArgoCD + patch dev in un unico apply atomico
#    Fonte: platform/argocd/kustomization.yaml
#      - base:  platform/argocd/install.yaml  (manifest vendorato v2.13.3)
#      - patch: platform/argocd/argocd-cm-patch.yaml  (insecure mode, annotation tracking)
# ---------------------------------------------------------------------------
info "Installo ArgoCD ${ARGOCD_VERSION} via kubectl apply -k platform/argocd/ ..."
kubectl apply -k "${REPO_ROOT}/platform/argocd/"

# ---------------------------------------------------------------------------
# 3. Attendi che i componenti principali siano pronti
# ---------------------------------------------------------------------------
info "Attendo argocd-server (timeout 3 min)..."
kubectl rollout status deployment/argocd-server \
  -n "${ARGOCD_NAMESPACE}" --timeout=180s

info "Attendo argocd-application-controller..."
kubectl rollout status statefulset/argocd-application-controller \
  -n "${ARGOCD_NAMESPACE}" --timeout=180s

info "Attendo argocd-repo-server..."
kubectl rollout status deployment/argocd-repo-server \
  -n "${ARGOCD_NAMESPACE}" --timeout=180s

# ---------------------------------------------------------------------------
# 4. Credenziali repo GitHub (necessarie per repo privato)
# ---------------------------------------------------------------------------
if [[ -n "${GH_TOKEN}" ]]; then
  info "Registro credenziali repo GitHub in ArgoCD..."
  kubectl create secret generic argocd-repo-lcn-lab \
    -n "${ARGOCD_NAMESPACE}" \
    --from-literal=type=git \
    --from-literal=url="${REPO_URL}" \
    --from-literal=username=git \
    --from-literal=password="${GH_TOKEN}" \
    --dry-run=client -o yaml \
  | kubectl label -f - argocd.argoproj.io/secret-type=repository --local -o yaml \
  | kubectl apply -f -
  info "Credenziali registrate."
else
  warn "GH_TOKEN non impostato: credenziali repo NON registrate."
  warn "Per repo privati esegui manualmente:"
  warn "  GH_TOKEN=<token> ./bootstrap/argocd-bootstrap.sh"
  warn "oppure usa la UI ArgoCD: Settings → Repositories."
fi

# ---------------------------------------------------------------------------
# 5. Root Application (app-of-apps)
# ---------------------------------------------------------------------------
info "Applico root Application (app-of-apps)..."
kubectl apply -n "${ARGOCD_NAMESPACE}" \
  -f "${REPO_ROOT}/apps/root-app.yaml"

# ---------------------------------------------------------------------------
# 6. Riepilogo
# ---------------------------------------------------------------------------
ADMIN_PASS=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode || echo "<non ancora disponibile>")

echo ""
echo "============================================================"
echo " ArgoCD ${ARGOCD_VERSION} — bootstrap completato"
echo "============================================================"
echo ""
echo " Accesso UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8090:80"
echo "   Apri: http://localhost:8090"
echo ""
echo " Credenziali iniziali:"
echo "   username: admin"
echo "   password: ${ADMIN_PASS}"
echo ""
echo " Stato pod:"
kubectl get pods -n "${ARGOCD_NAMESPACE}" --no-headers \
  | awk '{printf "   %-48s %s\n", $1, $3}'
echo ""
echo " Applications:"
kubectl get applications -n "${ARGOCD_NAMESPACE}" 2>/dev/null \
  | awk '{printf "   %s\n", $0}' || echo "   (nessuna ancora sincronizzata)"
echo "============================================================"
