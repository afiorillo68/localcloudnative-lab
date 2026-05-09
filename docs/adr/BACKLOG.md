# Backlog di decisioni future

Questo file e' una lista vivente di decisioni architetturali che sappiamo
di dover prendere in futuro, organizzate per fase del progetto. Non e'
un ADR ne' un sostituto: e' un appunto operativo per non dimenticare
cosa va deciso quando arrivera' il momento.

Quando una decisione viene presa, viene rimossa da qui e formalizzata
in un nuovo ADR (ADR-002, ADR-003, ...).

## Fase 3 — Popolamento componenti di piattaforma

### Lab vs production — Apisix admin key

**Status**: Documented design choice, lab-grade.

**Context**: The Apisix Helm chart ships with a default admin key
(`edd1c9f034335f136f87ad84b625c8f1`) that the Ingress Controller and
the gateway use to authenticate. This key is publicly documented and
appears as the default in the chart values.

**Decision**: Keep the default admin key for the lab. Justification:
the `apisix-admin` Service is `ClusterIP`-scoped and not exposed
externally; only pods in the cluster can reach it. The risk surface
is internal-only.

**Future evolution**: When promoting beyond the lab (Phase 5+),
replace the default key with a Sealed Secret-backed value via
`gatewayProxy.provider.controlPlane.auth.adminKey.valueFrom.secretKeyRef`.

### Lab vs enterprise — LoadBalancer implementation

**Status**: Documented design choice, not blocking.

**Context**: The lab uses `servicelb` (klipper-lb, k3s default) for
`LoadBalancer` Services. The enterprise target uses MetalLB (cf.
ADR-001). For a single-host lab, klipper-lb is sufficient and
idiomatic to k3d; MetalLB would add operational complexity without
proportional value.

**Future evolution**: replace klipper-lb with MetalLB if the lab
is extended to multi-host scenarios or if validating MetalLB-
specific behavior becomes necessary.

### ADR proposed — Etcd standalone for Apisix (Step 5)

**Status**: Proposed (to be ratified)

**Context**: The upstream Apache APISIX Helm chart includes
`bitnami/etcd` as a subchart. This subchart registers Helm hooks
(`pre-upgrade,pre-install`) that ArgoCD interprets as PreSync hooks.
The hook Job fails on first install due to a chicken-and-egg
dependency on a Secret that the same hook is supposed to create.

**Decision**: Disable the etcd subchart (`etcd.enabled: false`) and
deploy etcd standalone in the same namespace, using the upstream
CoreOS image `quay.io/coreos/etcd:v3.5.21` (multi-arch verified).
Configure Apisix to point at the standalone etcd via
`externalEtcd.host`.

**Consequences**:

- Removes Bitnami legacy from the Apisix subsystem
- Eliminates the Helm hook compatibility issue with ArgoCD
- Adds explicit ownership of the etcd component (small overhead)
- Single-node etcd is acceptable for the lab; for production-grade
  deployments a multi-node etcd cluster would be required

**To be promoted to formal ADR** when the lab Phase 3 is closed.

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

### External promotion strategy (post-MVP)

**Status**: Documented intent, not actionable until milestone reached.

**Trigger milestone**: Lab includes one or more end-to-end demo applications
that exercise the full stack (Angular → Apisix → Spring Boot → MongoDB with
OIDC via Keycloak). The demo apps should be designed to showcase both the
architecture's strengths AND limitations — case studies that include
honest discussion of where the pattern works and where it doesn't.

**Channels (multi-channel approach)**:

- **LinkedIn**: professional audience, focus on the methodology angle
  (Architect+Engineer+Decision-maker pattern as a case study)
- **Medium / dev.to**: technical audience, focus on the cloud-native lab
  angle (rigorous ADR-driven development on Apple Silicon)
- **Hacker News**: "Show HN" submission with the lab repository, framed
  around the unique combination of methodology + cloud-native discipline
- **Reddit**: relevant subreddits — r/kubernetes (lab angle), r/ClaudeAI
  (methodology angle), possibly r/devops

**What makes this distinctive (per market research, May 2026)**:

- The Architect+Engineer+Decision-maker pattern is documented elsewhere as
  best practice, but rarely as a case study with explicit failure episodes
- Cloud-native labs on Apple Silicon exist, but typically as tutorials —
  not as personal labs with enterprise-grade rigor (ADRs, methodology, runbooks)
- The combination of both, published as an honest narrative including
  what went wrong, was not found elsewhere

**Pre-promotion checklist** (to be executed when trigger milestone is reached):

- [ ] All ADRs reviewed and finalized (no PROPOSED entries on critical paths)
- [ ] Methodology document finalized with full set of episodes
- [ ] README polished for first-time visitors (clear "what / why / how")
- [ ] At least 2-3 demo apps documented as case studies
- [ ] Repository topics and description tuned for discoverability
- [ ] Decide on a canonical "anchor" article (likely Medium or personal site)
      and link to it from LinkedIn / Reddit / HN posts

**To be revisited when milestone is reached**.
