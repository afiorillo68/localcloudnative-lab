# Makefile — localcloudnative-lab
# Shortcut operativi per il laboratorio Kubernetes locale.
# Uso: make <target>

.PHONY: help argocd-ui lab-up lab-down lab-status

# Target di default: mostra i target disponibili
help:
	@echo ""
	@echo "  localcloudnative-lab — comandi disponibili"
	@echo ""
	@echo "  make argocd-ui     Apre il tunnel kubectl port-forward verso l'UI di Argo CD"
	@echo "  make lab-up        Avvia il cluster e attende readiness dei componenti"
	@echo "  make lab-down      Ferma il cluster k3d"
	@echo "  make lab-status    Mostra lo stato corrente del cluster e dei componenti"
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

# ------------------------------------------------------------------------------
# lab-down
#
# Ferma il cluster k3d-lcn-lab.
# NON ferma OrbStack (fuori scope: va gestito manualmente dall'utente).
# Verifica al termine che il cluster risulti effettivamente in stato STOPPED.
# ------------------------------------------------------------------------------
lab-down:
	@echo "------------------------------------------------------------"
	@echo "Stop del cluster k3d-lcn-lab"
	@echo "------------------------------------------------------------"
	@echo "Esecuzione: k3d cluster stop lcn-lab..."
	@k3d cluster stop lcn-lab \
	  && echo "[OK] Comando stop eseguito." \
	  || echo "[FAIL] Errore durante lo stop."
	@echo "------------------------------------------------------------"
	@echo "Verifica stato"
	@echo "------------------------------------------------------------"
	@k3d cluster list lcn-lab --no-headers
	@ACTIVE=$$(k3d cluster list lcn-lab --no-headers 2>/dev/null | awk '{print $$2}' | cut -d/ -f1); \
	if [ "$$ACTIVE" = "0" ]; then \
	  echo "[OK] Cluster fermato (0 server attivi)."; \
	else \
	  echo "[FAIL] Cluster non fermato correttamente ($$ACTIVE server attivi)."; \
	fi

# ------------------------------------------------------------------------------
# lab-up
#
# Avvia il cluster k3d-lcn-lab e attende la readiness delle componenti critiche.
# Stampa un report finale con lo stato di tutto.
# ------------------------------------------------------------------------------
lab-up:
	@echo "------------------------------------------------------------"
	@echo "Avvio del cluster k3d-lcn-lab"
	@echo "------------------------------------------------------------"
	@echo "Esecuzione: k3d cluster start lcn-lab..."
	@k3d cluster start lcn-lab \
	  && echo "[OK] Cluster avviato." \
	  || { echo "[FAIL] Errore durante l'avvio del cluster."; exit 1; }
	@echo "------------------------------------------------------------"
	@echo "Attesa readiness Argo CD"
	@echo "------------------------------------------------------------"
	@echo "Attendo argocd-server (timeout 60s)..."
	@kubectl -n argocd wait --for=condition=ready pod \
	    -l app.kubernetes.io/name=argocd-server --timeout=60s \
	  && echo "[OK] Argo CD pronto." \
	  || echo "[FAIL] Argo CD non pronto entro 60s."
	@echo "------------------------------------------------------------"
	@echo "Attesa readiness Sealed Secrets"
	@echo "------------------------------------------------------------"
	@echo "Attendo sealed-secrets-controller (timeout 60s)..."
	@kubectl -n platform-sealed-secrets wait --for=condition=ready pod \
	    -l app.kubernetes.io/name=sealed-secrets --timeout=60s \
	  && echo "[OK] Sealed Secrets pronto." \
	  || echo "[FAIL] Sealed Secrets non pronto entro 60s."
	@echo "------------------------------------------------------------"
	@echo "Attesa readiness MongoDB"
	@echo "------------------------------------------------------------"
	@echo "Attendo mongodb-0 (timeout 120s)..."
	@kubectl -n platform-mongodb wait --for=condition=ready pod \
	    -l app.kubernetes.io/name=mongodb --timeout=120s \
	  && echo "[OK] MongoDB pronto." \
	  || echo "[FAIL] MongoDB non pronto entro 120s."
	@echo "------------------------------------------------------------"
	@echo "Stato finale del lab"
	@echo "------------------------------------------------------------"
	@CLUSTER=$$(k3d cluster list lcn-lab --no-headers 2>/dev/null | awk '{print $$2}'); \
	ARGOCD=$$(kubectl -n argocd get pod -l app.kubernetes.io/name=argocd-server \
	    --no-headers 2>/dev/null | awk '{print $$3}' | head -1); \
	SEALEDSEC=$$(kubectl -n platform-sealed-secrets get pod \
	    -l app.kubernetes.io/name=sealed-secrets \
	    --no-headers 2>/dev/null | awk '{print $$3}' | head -1); \
	MONGODB=$$(kubectl -n platform-mongodb get pod \
	    -l app.kubernetes.io/name=mongodb \
	    --no-headers 2>/dev/null | awk '{print $$3}' | head -1); \
	MGSYNCH=$$(kubectl -n argocd get application mongodb \
	    -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null); \
	printf "%-25s %s\n" "Componente" "Stato"; \
	printf "%-25s %s\n" "-------------------------" "--------------------"; \
	printf "%-25s %s\n" "Cluster k3d"      "$${CLUSTER:-n/d}"; \
	printf "%-25s %s\n" "Argo CD"          "$${ARGOCD:-n/d}"; \
	printf "%-25s %s\n" "Sealed Secrets"   "$${SEALEDSEC:-n/d}"; \
	printf "%-25s %s\n" "MongoDB"          "$${MONGODB:-n/d}"; \
	printf "%-25s %s\n" "Application mongodb" "$${MGSYNCH:-n/d}"

# ------------------------------------------------------------------------------
# lab-status
#
# Diagnostica rapida senza modifiche al sistema.
# Funziona anche se il cluster e' spento: in quel caso lo segnala chiaramente.
# ------------------------------------------------------------------------------
lab-status:
	@echo "------------------------------------------------------------"
	@echo "Stato cluster k3d"
	@echo "------------------------------------------------------------"
	@k3d cluster list lcn-lab --no-headers 2>/dev/null; \
	ACTIVE=$$(k3d cluster list lcn-lab --no-headers 2>/dev/null | awk '{print $$2}' | cut -d/ -f1); \
	if [ "$$ACTIVE" = "0" ] || [ -z "$$ACTIVE" ]; then \
	  echo "Cluster fermato. Usa 'make lab-up' per avviarlo."; \
	  exit 0; \
	fi; \
	echo "------------------------------------------------------------"; \
	echo "Stato componenti di piattaforma"; \
	echo "------------------------------------------------------------"; \
	for NS in argocd platform-sealed-secrets platform-mongodb; do \
	  TOTAL=$$(kubectl get pods -n $$NS --no-headers 2>/dev/null | wc -l | tr -d ' '); \
	  RUNNING=$$(kubectl get pods -n $$NS --no-headers 2>/dev/null | grep -c "Running" || true); \
	  printf "%-35s %s/%s Running\n" "$$NS" "$$RUNNING" "$$TOTAL"; \
	done; \
	echo "------------------------------------------------------------"; \
	echo "Stato Argo CD Applications"; \
	echo "------------------------------------------------------------"; \
	kubectl -n argocd get applications \
	  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status \
	  --no-headers 2>/dev/null; \
	echo "------------------------------------------------------------"; \
	echo "Risorse cluster (kubectl top)"; \
	echo "------------------------------------------------------------"; \
	kubectl top pods --all-namespaces --no-headers 2>/dev/null \
	  | awk '{cpu+=$$3; mem+=$$4} END {printf "CPU totale: %s    RAM totale: %s\n", cpu"m", mem"Mi"}' \
	  || echo "metrics-server non disponibile (kubectl top non supportato)."
