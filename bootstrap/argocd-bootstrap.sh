#!/usr/bin/env bash
# =============================================================================
# bootstrap/argocd-bootstrap.sh
# Bootstrap ArgoCD nel cluster lcn-lab (Fase 2).
#
# Uso:
#   ./bootstrap/argocd-bootstrap.sh
#   REPO_URL=https://github.com/OWNER/localcloudnative-lab \
#     ./bootstrap/argocd-bootstrap.sh
#
# Il parametro REPO_URL serve solo per applicare la root Application
# (app-of-apps). Se non specificato, ArgoCD viene installato ma la root app
# NON viene applicata: farlo manualmente dopo aver pushato il repo su GitHub.
#
# Prerequisiti: kubectl, helm nel PATH e cluster lcn-lab raggiungibile.
# =============================================================================
set -euo pipefail

ARGOCD_VERSION="v2.13.3"
ARGOCD_NAMESPACE="argocd"
ARGOCD_INSTALL_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_URL="${REPO_URL:-}"

# ---------------------------------------------------------------------------
# Colori
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERR]${NC}   $*" >&2; }

# ---------------------------------------------------------------------------
# Preflight: verifica che kubectl punti al cluster corretto
# ---------------------------------------------------------------------------
CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "none")
if [[ "${CURRENT_CTX}" != "k3d-lcn-lab" ]]; then
  error "Context attuale: '${CURRENT_CTX}'. Atteso: 'k3d-lcn-lab'."
  error "Esegui: kubectl config use-context k3d-lcn-lab"
  exit 1
fi
info "Context kubectl: ${CURRENT_CTX} — OK"

# ---------------------------------------------------------------------------
# 1. Namespace argocd
# ---------------------------------------------------------------------------
info "Creo namespace ${ARGOCD_NAMESPACE} (idempotente)..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# 2. Installa ArgoCD (manifest upstream)
# ---------------------------------------------------------------------------
info "Installo ArgoCD ${ARGOCD_VERSION}..."
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "${ARGOCD_INSTALL_MANIFEST}"

# ---------------------------------------------------------------------------
# 3. Patch ConfigMap: modalita' dev (insecure, tracking via annotation)
# ---------------------------------------------------------------------------
info "Applico patch ConfigMap dev (insecure mode)..."
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "${REPO_ROOT}/platform/argocd/argocd-cm-patch.yaml"

# Forza il restart dell'argocd-server per recepire la patch
kubectl rollout restart deployment argocd-server -n "${ARGOCD_NAMESPACE}" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 4. Attendi che ArgoCD sia pronto
# ---------------------------------------------------------------------------
info "Attendo che argocd-server sia pronto (timeout 3 minuti)..."
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=180s

info "Attendo che application-controller sia pronto..."
kubectl rollout status statefulset/argocd-application-controller \
  -n "${ARGOCD_NAMESPACE}" --timeout=180s 2>/dev/null || \
kubectl rollout status deployment/argocd-application-controller \
  -n "${ARGOCD_NAMESPACE}" --timeout=180s 2>/dev/null || true

# ---------------------------------------------------------------------------
# 5. Root Application (app-of-apps) — solo se REPO_URL e' impostato
# ---------------------------------------------------------------------------
if [[ -n "${REPO_URL}" ]]; then
  info "Applico root Application (app-of-apps) con repo: ${REPO_URL}"
  REPO_URL="${REPO_URL}" envsubst < "${REPO_ROOT}/apps/root-app.yaml" \
    | kubectl apply -n "${ARGOCD_NAMESPACE}" -f -
else
  warn "REPO_URL non impostato: root Application NON applicata."
  warn "Dopo aver pushato il repo su GitHub, esegui:"
  warn "  REPO_URL=https://github.com/OWNER/localcloudnative-lab \\"
  warn "    envsubst < apps/root-app.yaml | kubectl apply -n argocd -f -"
fi

# ---------------------------------------------------------------------------
# 6. Password admin
# ---------------------------------------------------------------------------
ADMIN_PASS=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode || echo "non trovata")

echo ""
echo "============================================================"
echo " ArgoCD installato — ${ARGOCD_VERSION}"
echo "============================================================"
echo ""
echo " Accesso UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8443:443"
echo "   Apri: http://localhost:8443"
echo "   (HTTPS disabilitato grazie al patch insecure mode)"
echo ""
echo "   oppure, con port-forward sulla porta 80 del server:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8090:80"
echo "   Apri: http://localhost:8090"
echo ""
echo " Credenziali iniziali:"
echo "   username: admin"
echo "   password: ${ADMIN_PASS}"
echo ""
echo " Per cambiare la password admin:"
echo "   argocd account update-password"
echo "   (richiede argocd CLI: brew install argocd)"
echo ""
echo " Stato componenti:"
kubectl get pods -n "${ARGOCD_NAMESPACE}" --no-headers \
  | awk '{printf "   %-45s %s\n", $1, $3}'
echo "============================================================"
