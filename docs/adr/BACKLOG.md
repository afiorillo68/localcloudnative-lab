# Backlog di decisioni future

Questo file e' una lista vivente di decisioni architetturali che sappiamo
di dover prendere in futuro, organizzate per fase del progetto. Non e'
un ADR ne' un sostituto: e' un appunto operativo per non dimenticare
cosa va deciso quando arrivera' il momento.

Quando una decisione viene presa, viene rimossa da qui e formalizzata
in un nuovo ADR (ADR-002, ADR-003, ...).

## Fase 3 — Popolamento componenti di piattaforma

### Keycloak
- [ ] Database: PostgreSQL in-cluster o database embedded H2? (per
      pattern enterprise-coerente, PostgreSQL; per setup leggero, H2)
- [ ] Hostname: come esponiamo Keycloak prima dell'installazione di
      Apisix? (port-forward iniziale, poi rotta Apisix in seconda
      battuta)
- [ ] Realm di default: quanti realm creiamo? un singolo realm "lcn"
      per gli esperimenti, o un realm per ambiente?
- [ ] Utenti seed: creiamo via Keycloak Operator, via Helm postsync
      hook, via Job custom? (probabilmente Job che gira `kcadm.sh`)
- [ ] Theme custom: lasciamo quello di default o ne aggiungiamo uno?
      (skip per Fase 3, eventualmente in futuro)

### Apache Apisix
- [ ] Configurazione storage: ETCD (default) o PostgreSQL?
      (raccomandazione storica: ETCD; il documento DCPP cita anche
      PostgreSQL come alternativa ma e' sotto verifica)
- [ ] Strategia rotte: definite via CRD `ApisixRoute` (Apisix Ingress
      Controller) o via API admin? (CRD e' GitOps-compatibile, API
      admin no)
- [ ] Esposizione: Apisix prende le porte 80/443 dal LoadBalancer di
      k3d, e i Service interni vengono raggiunti via Apisix. Conferma?
- [ ] Plugin abilitati: minimo essenziale (auth via OIDC con Keycloak,
      rate limiting) o set piu' ampio?

### Patch ad Argo CD
- [ ] Aggiungere `kustomize.buildOptions: --enable-helm` al
      ConfigMap `argocd-cm` prima di Fase 3 (gotcha annotato in
      ADR-001 D8)

## Fase 4 — Workloads applicativi

### Naming dei namespace dei workloads
- [ ] Pattern: `workloads-<dominio>` (es. `workloads-gis`,
      `workloads-ai`)? Singolo namespace `workloads`? Decidere con
      criterio simile a D4 della piattaforma.

### Strategia di build delle immagini
- [ ] CI/CD: GitHub Actions, build locale via `docker build`, oppure
      Tekton/Argo Workflows in-cluster?
- [ ] Registry: registry locale di k3d (`k3d-registry.localhost:5000`)
      per dev, GitHub Container Registry per immagini "stable"?
- [ ] Versioning: tag per commit SHA, semver, o entrambi?

### Struttura per tipologia di workload
- [ ] Microservizi Spring Boot: chart Helm custom, manifest puri, o
      template generico riusabile?
- [ ] Frontend Angular: serving via Nginx in Kubernetes, oppure
      build statica in MinIO?
- [ ] Caso GIS: PostGIS come DB? Tile server (geoserver, t-rex)?
- [ ] Caso AI/SLM: dove gira il modello? (Ollama come pod? llama.cpp
      server? container con weights montati come volume?). Vector
      store: Qdrant, Weaviate, pgvector?

## Fase 5 — Osservabilita' (se attivata)

- [ ] Stack completo (Loki + Grafana + Tempo + Mimir) o sottoinsieme?
- [ ] On-demand (start/stop con make) o sempre attivo?
- [ ] Visualizzazione: dashboard custom o solo "out of the box"?

## Trasversali (qualunque fase)

- [ ] Backup del cluster k3d: cosa salvare, dove, come ripristinare?
- [ ] Promotion via Git tra ambienti: quando attivare un secondo
      ambiente, come gestire il flusso `dev` -> `stage`?
- [ ] Eventuale evoluzione a multi-cluster: si fa o no? (in caso, come
      simuliamo il pattern DCPP a tre cluster?)
- [ ] Aggiornamento Argo CD a v3.x: pianificato per inizio Fase 3
      (ADR-001 cita Argo CD 3.0.5 come versione DCPP target)
- [ ] Monitoraggio della sopravvivenza del registry `docker.io/bitnamilegacy`
      (cfr. ADR-002): verificare ogni 3-6 mesi se Broadcom ha annunciato
      date di smantellamento. In tal caso, scrivere un ADR successivo
      che superseda ADR-002 e definisca la nuova rotta.
- [ ] Verifica preventiva di compatibilita' arm64 per ogni nuovo
      componente di piattaforma o workload (cfr. ADR-003 driver
      arm64). Da applicare a tutte le decisioni di Step 4
      (Keycloak), Step 5 (Apisix), e Fase 4 (workload applicativi).

## Come usare questo file

- Quando inizi una fase, leggi le voci corrispondenti.
- Quando una decisione e' matura, la discuti (qui in chat con
  l'Architect, o autonomamente per decisioni tattiche), la rimuovi
  da questo file e la formalizzi in un ADR se ha conseguenze di
  lungo periodo.
- Quando emergono nuove decisioni durante lo sviluppo, le aggiungi
  qui prima di passarle a Code per esecuzione.
