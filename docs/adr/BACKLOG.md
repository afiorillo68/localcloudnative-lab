# Backlog decisioni architetturali

Questo documento raccoglie le decisioni architetturali che sono state
identificate come rilevanti ma non ancora prese, perche' il contesto
non e' ancora maturo o perche' dipendono da fasi future del progetto.

Quando una decisione di questo backlog viene ratificata, viene rimossa
da qui e formalizzata in un nuovo ADR (numerato progressivamente dopo
ADR-001).

---

## Decisioni pendenti

### B1 — Strategia CI/CD per i workloads applicativi

**Fase attesa**: Fase 4+ (quando i workloads vengono introdotti)

**Domanda aperta**: come si gestisce il ciclo build → push immagine →
aggiornamento manifest → sync Argo CD?

**Opzioni da valutare**:
- GitHub Actions per build e push su registry (registry.localhost o GHCR).
- Image updater di Argo CD per aggiornamento automatico del tag immagine
  nel manifest.
- Promotion manuale tra ambienti (dev → stage) via PR o tag Git.
- Tekton on-cluster (pattern enterprise, sproporzionato per un lab).

**Dipendenze**: B2 (naming namespace workloads), B4 (strategia pinning
revisione per ambienti multipli).

---

### B2 — Naming convention per i namespace dei workloads

**Fase attesa**: inizio Fase 4

**Domanda aperta**: ADR-001 D4 definisce il prefisso `platform-*` per i
componenti di piattaforma. I namespace dei microservizi e frontend
seguiranno uno schema diverso. Quale?

**Opzioni da valutare**:
- `workloads-<servizio>` (simmetrico con `platform-<componente>`).
- `<dominio>-<servizio>` (es. `tifoserie-frontend`, `tifoserie-api`).
- Namespace unico `workloads` condiviso da tutti i workloads.

**Dipendenze**: nessuna, ma deve essere decisa prima di creare le prime
Application Argo CD per i workloads.

---

### B3 — Pattern di osservabilita'

**Fase attesa**: Fase 5+ (opzionale)

**Domanda aperta**: se e quando introdurre uno stack di osservabilita'.
Il target DCPP usa Loki + Grafana + Tempo + Mimir. Quanto di questo
e' replicabile (e utile) in un lab su Mac con risorse limitate?

**Opzioni da valutare**:
- Stack completo LGTM (Loki, Grafana, Tempo, Mimir) — fedele al target
  ma pesante su RAM.
- Solo Grafana + Loki (logging, no tracing, no metrics avanzate).
- Nessuno stack dedicato: usare `kubectl logs` e port-forward per le
  dashboard native (es. Keycloak, Argo CD) — approccio minimalista.
- Prometheus + Grafana senza Loki/Tempo — pattern alternativo comune.

**Dipendenze**: nessuna tecnica, ma ha senso solo dopo che i workloads
applicativi (Fase 4) emettono dati.

---

### B4 — Strategia pinning revisione per il secondo ambiente

**Fase attesa**: quando viene attivato un secondo overlay (es. `stage`)

**Domanda aperta**: ADR-001 D5 decide `targetRevision: HEAD` per `dev`.
Se viene attivato un ambiente `stage` (runbook in `docs/how-to/`), la
sua Application dovrebbe puntare a HEAD o a tag pinniati?

**Opzioni da valutare**:
- `stage` punta a tag versionati (es. `v1.0.0`): richiede una strategia
  di tagging e un processo di promotion esplicito.
- `stage` punta a un branch dedicato (`release/stage`): la promotion
  diventa un merge da `main` al branch.
- Anche `stage` su HEAD: semplice, ma annulla la separazione semantica
  tra ambienti.

**Dipendenze**: ADR-001 D5 (da marcare come parzialmente Superseded).

---

### B5 — Strategia backup e disaster recovery del cluster k3d

**Fase attesa**: Fase 3 (prima della messa in produzione del lab)

**Domanda aperta**: k3d e' volatile per design (cluster effimeri su
Docker). Cosa va salvato prima di un `k3d cluster delete`?

**Elementi candidati al backup**:
- Chiave master Sealed Secrets (gia' indicata in ADR-001 D7 come
  critica — va su password manager, non nel repo).
- State di Argo CD (Application objects): gia' in Git, nessun backup
  aggiuntivo necessario.
- PersistentVolumeClaim di MongoDB: i dati di test sono recuperabili
  dal seed, ma se si accumulano dati di sessione vale la pena definire
  una strategia di dump.
- Eventuali segreti creati a mano (`kubectl create secret`) fuori dal
  flusso Sealed Secrets: andrebbero eliminati o migrati.

**Dipendenze**: Fase 3 (Sealed Secrets, MongoDB).

---

### B6 — Evoluzione a pattern multi-cluster

**Fase attesa**: ipotetica Fase 6+ (se il lab vuole simulare il modello DCPP)

**Domanda aperta**: DCPP usa tre cluster distinti (management, dev, prod).
Vale la pena replicarlo con k3d multi-cluster su Mac?

**Opzioni da valutare**:
- Due cluster k3d (`lcn-management` + `lcn-dev`): Argo CD su management,
  Application deployate su `lcn-dev`.
- Tre cluster k3d (management + dev + stage): fedele al modello DCPP,
  ma l'overhead RAM potrebbe essere proibitivo.
- Mantenere il lab single-cluster e documentare le differenze rispetto
  al target come "delta architetturale accettato" (scelta piu' probabile).

**Dipendenze**: ADR-001 D3 (self-management Argo CD, da rivedere se si
introduce un cluster di management).

---

## Decisioni risolte (rimosse dal backlog)

| ID | Titolo | ADR |
|---|---|---|
| — | Strategia GitOps iniziale (8 decisioni) | [ADR-001](0001-strategia-gitops.md) |

---

## Note operative

- Le decisioni di questo backlog sono ordinate per fase attesa, non per
  priorita'.
- Una decisione non e' "urgente" finche' non si arriva alla fase che
  la richiede.
- Quando una decisione viene presa, rimuovila da qui e aggiungi il
  riferimento all'ADR nella tabella "Decisioni risolte".
