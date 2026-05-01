# Makefile — localcloudnative-lab
# Shortcut operativi per il laboratorio Kubernetes locale.
# Uso: make <target>

.PHONY: help argocd-ui

# Target di default: mostra i target disponibili
help:
	@echo ""
	@echo "  localcloudnative-lab — comandi disponibili"
	@echo ""
	@echo "  make argocd-ui     Apre il tunnel kubectl port-forward verso l'UI di Argo CD"
	@echo ""

# ------------------------------------------------------------------------------
# argocd-ui
#
# Apre un tunnel kubectl port-forward verso argocd-server (HTTPS, porta 443).
# L'accesso avviene su https://localhost:8090.
# Il browser avvertira' del certificato self-signed: accettare e proseguire.
#
# Prerequisiti verificati prima di avviare il tunnel:
#   1. Il cluster Kubernetes e' raggiungibile (kubectl cluster-info).
#   2. La porta 8090 non e' gia' in uso (lsof -i :8090).
# ------------------------------------------------------------------------------
argocd-ui:
	@# --- Controllo 1: cluster raggiungibile ---
	@echo "→ Verifico che il cluster sia raggiungibile..."
	@kubectl cluster-info > /dev/null 2>&1 || { \
	  echo ""; \
	  echo "  ERRORE: cluster Kubernetes non raggiungibile."; \
	  echo ""; \
	  echo "  Possibili cause:"; \
	  echo "    • OrbStack non e' avviato  →  apri l'app OrbStack"; \
	  echo "    • Il cluster lcn-lab non esiste  →  k3d cluster list"; \
	  echo "    • Il cluster e' fermo  →  k3d cluster start lcn-lab"; \
	  echo "    • kubectl punta al cluster sbagliato  →  kubectl config use-context k3d-lcn-lab"; \
	  echo ""; \
	  exit 1; \
	}
	@echo "  OK: cluster raggiungibile."
	@# --- Controllo 2: porta 8090 libera ---
	@echo "→ Verifico che la porta 8090 sia libera..."
	@lsof -i :8090 -sTCP:LISTEN > /dev/null 2>&1 && { \
	  echo ""; \
	  echo "  ERRORE: la porta 8090 e' gia' occupata."; \
	  echo ""; \
	  echo "  Processo in ascolto:"; \
	  lsof -i :8090 -sTCP:LISTEN | awk 'NR>1 {printf "    PID %-6s %s\n", $$2, $$1}'; \
	  echo ""; \
	  echo "  Soluzioni:"; \
	  echo "    • Chiudi il processo che occupa la porta"; \
	  echo "    • Oppure termina un eventuale port-forward precedente:"; \
	  echo "      kill \$$(lsof -ti :8090)"; \
	  echo ""; \
	  exit 1; \
	} || true
	@echo "  OK: porta 8090 libera."
	@# --- Avvio tunnel ---
	@echo ""
	@echo "┌─────────────────────────────────────────────────────────┐"
	@echo "│  Argo CD UI                                             │"
	@echo "│                                                         │"
	@echo "│  URL:  https://localhost:8090                           │"
	@echo "│  user: admin                                            │"
	@echo "│  pass: kubectl -n argocd get secret                    │"
	@echo "│          argocd-initial-admin-secret                   │"
	@echo "│          -o jsonpath='{.data.password}'                │"
	@echo "│          | base64 --decode; echo                       │"
	@echo "│                                                         │"
	@echo "│  Il browser avvertira' del certificato self-signed:    │"
	@echo "│  e' normale, clicca 'Avanzate → Procedi comunque'.    │"
	@echo "│                                                         │"
	@echo "│  Ctrl-C per chiudere il tunnel.                        │"
	@echo "└─────────────────────────────────────────────────────────┘"
	@echo ""
	kubectl port-forward -n argocd svc/argocd-server 8090:443
