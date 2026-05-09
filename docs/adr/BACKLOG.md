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

### Argo CD: federation OIDC con Keycloak

**Status**: Proposed for Phase 5+.

**Context**: Argo CD currently uses the auto-generated initial admin
password (stored in Bitwarden as
`lcn-lab — Argo CD admin password (initial, lab-grade)`). This
password is regenerated on every cluster reset, requiring manual
Bitwarden update each time.

**Decision**: Configure Argo CD OIDC integration with Keycloak.
Users log in to Argo CD via Keycloak's `lcn` realm. The local admin
password is retained as break-glass fallback only.

**Prerequisites**:

- Keycloak operational ✓ (Phase 3 Step 4 completed)
- Apisix operational with TLS termination ✓ (Phase 3 Step 5 completed)
- A Keycloak client `argocd` configured in the `lcn` realm
- Argo CD configured with the OIDC settings pointing at Keycloak

**To be promoted to formal step** when ready to start.

## Trasversali (qualunque fase)

### Cosmetic drift on StatefulSet volumeClaimTemplates

**Status**: Open, low priority, recurring pattern.

**Context**: StatefulSets with `volumeClaimTemplates` (currently:
`mongodb`, `etcd-standalone`) trigger cosmetic drift in Argo CD.
The Kubernetes API server auto-populates `apiVersion: v1` and
`kind: PersistentVolumeClaim` on each template entry, fields that
are not present in the Git manifest. Argo CD reports this as
`OutOfSync` even though the actual configuration matches.

**Workaround**: add the two fields explicitly in the Git manifest's
`volumeClaimTemplates` entries. Already applied to MongoDB. Pending
for `platform/apisix/base/etcd-standalone.yaml`.

**Proper fix (future)**: configure `ignoreDifferences` on the
respective Argo CD Applications for paths
`spec.volumeClaimTemplates[*].apiVersion` and
`spec.volumeClaimTemplates[*].kind`. Centralized solution scaling
to any future StatefulSet.

### Backup e ripristino

- [ ] Backup del cluster k3d: cosa salvare, dove, come ripristinare?

### Promotion tra ambienti

- [ ] Promotion via Git tra ambienti: quando attivare un secondo
      ambiente, come gestire il flusso `dev` -> `stage`?

### Multi-cluster

- [ ] Eventuale evoluzione a multi-cluster: si fa o no? (in caso, come
      simuliamo il pattern DCPP a tre cluster?)

### Aggiornamento Argo CD

- [ ] Aggiornamento Argo CD a v3.x (ADR-001 cita Argo CD 3.0.5 come
      versione DCPP target). La v2.13.3 in uso e' funzionale; valutare
      se l'upgrade va fatto prima di Fase 4 o rimandato.

### Monitoraggio Bitnami legacy

- [ ] Monitoraggio della sopravvivenza del registry
      `docker.io/bitnamilegacy` (cfr. ADR-002): verificare ogni
      3-6 mesi se Broadcom ha annunciato date di smantellamento.
      In tal caso, scrivere un ADR successivo che superseda ADR-002
      e definisca la nuova rotta.

### Verifica preventiva arm64

- [ ] Driver arm64 (cfr. ADR-003) — gia' applicato a Step 4
      (Keycloak), Step 5 (Apisix), etcd standalone. Da applicare
      a tutte le decisioni di Fase 4 (workload applicativi) e
      successive.

### Argo CD: replace initial admin password

**Status**: Postponed to Phase 5+ (will be obsolete after OIDC
federation).

**Context**: Currently Argo CD uses the auto-generated
`argocd-initial-admin-secret`, regenerated at each cluster reset.
The current operational pattern is: extract password after
bootstrap, save to Bitwarden manually, repeat on every reset.

**Future**: this becomes irrelevant once OIDC federation with
Keycloak is configured (see Fase 5 — Argo CD OIDC integration).
The local admin password remains only as break-glass.

## External promotion strategy (post-MVP)

**Status**: Documented intent, not actionable until milestone reached.

**Trigger milestone**: Lab includes one or more end-to-end demo
applications that exercise the full stack (Angular → Apisix →
Spring Boot → MongoDB with OIDC via Keycloak). The demo apps should
be designed to showcase both the architecture's strengths AND
limitations — case studies that include honest discussion of where
the pattern works and where it doesn't.

**Channels (multi-channel approach)**:

- **LinkedIn**: professional audience, focus on the methodology
  angle (Architect+Engineer+Decision-maker pattern as a case study)
- **Medium / dev.to**: technical audience, focus on the cloud-native
  lab angle (rigorous ADR-driven development on Apple Silicon)
- **Hacker News**: "Show HN" submission with the lab repository,
  framed around the unique combination of methodology + cloud-native
  discipline
- **Reddit**: relevant subreddits — r/kubernetes (lab angle),
  r/ClaudeAI (methodology angle), possibly r/devops

**What makes this distinctive (per market research, May 2026)**:

- The Architect+Engineer+Decision-maker pattern is documented
  elsewhere as best practice, but rarely as a case study with
  explicit failure episodes
- Cloud-native labs on Apple Silicon exist, but typically as
  tutorials — not as personal labs with enterprise-grade rigor
  (ADRs, methodology, runbooks)
- The combination of both, published as an honest narrative
  including what went wrong, was not found elsewhere

**Pre-promotion checklist** (to be executed when trigger milestone
is reached):

- [ ] All ADRs reviewed and finalized (no PROPOSED entries on
      critical paths)
- [ ] Methodology document finalized with full set of episodes
- [ ] README polished for first-time visitors (clear "what / why /
      how")
- [ ] At least 2-3 demo apps documented as case studies
- [ ] Repository topics and description tuned for discoverability
- [ ] Decide on a canonical "anchor" article (likely Medium or
      personal site) and link to it from LinkedIn / Reddit / HN
      posts

**To be revisited when milestone is reached**.

## Come usare questo file

- Quando inizi una fase, leggi le voci corrispondenti.
- Quando una decisione e' matura, la discuti (qui in chat con
  l'Architect, o autonomamente per decisioni tattiche), la rimuovi
  da questo file e la formalizzi in un ADR se ha conseguenze di
  lungo periodo.
- Quando emergono nuove decisioni durante lo sviluppo, le aggiungi
  qui prima di passarle a Code per esecuzione.
