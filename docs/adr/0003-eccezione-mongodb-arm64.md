# ADR-003 — Eccezione platform-aware per MongoDB e introduzione del driver di compatibilita' arm64

## Status

Accepted — ratificato in conversazione architetturale del 1 maggio 2026,
durante l'esecuzione dello Step 3 della Fase 3, dopo tre tentativi di
deploy non andati a buon fine per problemi di compatibilita' di piattaforma.

Supersede parziale di ADR-002 limitatamente a MongoDB (gli altri componenti
dell'ecosistema Bitnami restano sotto ADR-002 finche' non emergono vincoli
analoghi).

## Context

L'esecuzione dello Step 3 della Fase 3 (deploy di MongoDB come primo
componente di piattaforma popolato) ha incontrato problemi di
compatibilita' di piattaforma non previsti nelle conversazioni
architetturali di ADR-001 D8 e ADR-002:

1. **Tentativo 1**: chart Bitnami `mongodb` v18.6.31 con immagini su
   `docker.io/bitnamilegacy/`. Il pod resta in `ImagePullBackOff` con
   errore `no match for platform in manifest`. Diagnosi: le immagini
   `bitnamilegacy/mongodb` sono pubblicate **solo per linux/amd64**.

2. **Verifica del nodo k3d**: `kubectl get nodes -o jsonpath='{...architecture}'`
   restituisce `arm64`. Il cluster gira nativamente su Apple Silicon
   senza emulazione. La piattaforma host (MacBook M-series) e' arm64
   nativa.

3. **Verifica del manifest**: `docker manifest inspect docker.io/bitnamilegacy/mongodb:8.0.13-debian-12-r0`
   conferma la presenza di un solo manifest per `linux/amd64`.

Questa scoperta evidenzia un **vuoto metodologico** nelle decisioni
architetturali pregresse: le sessioni di design non hanno verificato
in modo sistematico la compatibilita' arm64 dei chart e delle immagini
prima di confermarne l'adozione. La sequenza di tentativi (Bitnami →
Chainguard → bitnamilegacy → impasse arm64) e' una conseguenza diretta
di questo vuoto.

L'ADR-003 affronta la situazione su due livelli:

- **Livello tattico**: definisce la rotta per MongoDB in modo che il
  deploy funzioni effettivamente su arm64.
- **Livello strategico**: introduce un nuovo decision driver permanente
  per tutte le decisioni di tecnologia successive, evitando che lo
  stesso pattern si ripeta su Keycloak, Apisix, e altri componenti
  futuri.

## Decision drivers

Il driver originario di ADR-001 ("riproducibilita'", "allineamento al
target enterprise", "valore didattico", "semplicita' operativa",
"velocita' di iterazione") resta valido. Si aggiunge:

- **Compatibilita' con la piattaforma host (arm64)**: ogni chart,
  immagine container, o componente di piattaforma deve essere verificato
  per il supporto arm64 **prima** della ratifica della scelta in sede
  architetturale. La verifica e' considerata parte integrante della
  conversazione di design, non un dettaglio operativo da scoprire in
  fase di implementazione. Eventuali deroghe (es. accettazione consapevole
  di emulazione Rosetta, fallback a single-arch) vanno documentate caso
  per caso.

Questo driver si applica retroattivamente a tutti i componenti gia'
deployati o in fase di deploy nel lab (verifica positiva in tutti i casi
attuali: Argo CD, Sealed Secrets, k3d) e prospettivamente a tutti i
componenti di Fase 3 e successive (Keycloak, Apache Apisix, eventuali
PostgreSQL, eventuali workload di Fase 4).

## Considered options (per MongoDB)

Sono state valutate quattro alternative concrete dopo l'identificazione
del vincolo arm64. Si rimanda alla conversazione architetturale per la
discussione completa; sintesi qui.

### Alternativa A — Manifest puri Kustomize con immagine `mongo:8.0` ufficiale

Scrivere a mano `StatefulSet`, `Service`, `ConfigMap` e init script per
MongoDB, usando l'immagine `mongo:8.0` ufficiale di Docker Hub
(mantenuta da MongoDB Inc., multi-arch nativa).

**Pro**:
- L'immagine `mongo:8.0` ufficiale e' multi-arch nativa (amd64 + arm64).
- Manutenzione attiva da MongoDB Inc.
- Pattern leggibile, ~80-120 righe di YAML totali.
- Zero dipendenze da Bitnami, zero Operator da imparare.

**Contro**:
- Rompe il pattern stabilito in ADR-001 D8 (Kustomize con Helm generator)
  per questo singolo componente.
- Init logic per replica set e creazione utente applicativo da scrivere
  a mano (cose che il chart Bitnami avrebbe dato gratis).

### Alternativa B — MongoDB Controllers for Kubernetes Operator (versione unificata 1.x)

Operator pattern moderno, multi-arch nativo, mantenuto attivamente da
MongoDB Inc. Si gestisce un Custom Resource che descrive il deploy.

**Pro**:
- Multi-arch nativo.
- Manutenzione attiva, indipendenza da Bitnami.

**Contro**:
- Tecnologia in fase di transizione: l'Operator "unificato" v1.x e'
  recente, documentazione in evoluzione, esempi non sempre allineati.
- Sproporzionato per un lab single-instance: l'Operator e' progettato
  per scenari multi-replica e multi-tenant complessi.
- Cambia il paradigma: introduce il pattern Operator nel lab senza
  necessita' didattica primaria.
- Curva di apprendimento aggiuntiva.

### Alternativa C — MongoDB Community Operator (versione vecchia "Community-only")

Operator pre-unificazione, con issue aperte specifiche per arm64
(`mongodb/mongodb-kubernetes-operator` issue #1514 e #1420).

**Pro**:
- Esistono workaround documentati dalla community per arm64.

**Contro**:
- Issue aperte non risolte.
- MongoDB Inc. lo sta gradualmente sostituendo con la versione unificata
  (Alternativa B): scelta che invecchierebbe rapidamente.

### Alternativa D — Emulazione Rosetta con chart Bitnami originale

OrbStack supporta Rosetta 2 per eseguire container amd64 emulati su
Apple Silicon. Il chart Bitnami funzionerebbe sotto emulazione.

**Pro**:
- Zero modifiche al pattern architetturale ADR-001 D8 / ADR-002.

**Contro**:
- Performance degradate (database server con I/O intensivo soffre
  l'emulazione).
- Compatibilita' non garantita al 100% per scenari edge case (transazioni,
  replica, ecc.).
- Costruisce cerotti su cerotti: immagine archiviata + emulazione.

## Decision

**Alternativa A — Manifest puri Kustomize con immagine `mongo:8.0`
ufficiale Docker Hub**.

Concretamente:

- `platform/mongodb/base/` conterra' un set di manifest scritti a mano:
  `Namespace`, `StatefulSet`, `Service` (headless per replica set
  internal addressing + ClusterIP per accesso applicativo), `ConfigMap`
  con script di inizializzazione, eventuale `PodDisruptionBudget`.
- L'immagine usata e' `mongo:8.0` (Docker Hub ufficiale, multi-arch).
- Le credenziali continuano a essere gestite via Sealed Secrets, come
  da ADR-001 D7 (no eccezione su questo).
- La struttura `base/ + overlays/dev/` rimane (ADR-001 D6 si applica
  invariato).
- L'init logic per inizializzazione replica set e creazione utente
  applicativo viene gestita via `initContainer` o post-start hook con
  `mongosh` invocato da uno script.

## Consequences

### Positive

- Il deploy di MongoDB funziona effettivamente su Apple Silicon arm64.
- Indipendenza da Bitnami / Broadcom per il componente database
  principale del lab.
- Pattern didatticamente molto leggibile: chi clona il repo vede
  manifest Kubernetes "puri" che spiegano cosa succede senza la magia
  del chart Helm.
- L'eccezione e' circoscritta e documentata: nessun precedente di
  "ogni componente decide caso per caso" senza criterio.

### Negative

- ADR-001 D8 ora ha un'eccezione esplicita. Il pattern non e' piu'
  applicato uniformemente a tutti i componenti di piattaforma.
- Init script per replica set sono codice custom da mantenere. Se in
  futuro l'inizializzazione di MongoDB cambiera' (es. nuovi parametri),
  il manifest va aggiornato a mano.
- Il chart Bitnami avrebbe gestito automaticamente alcune feature
  collaterali (es. metrics exporter Prometheus, backup hook): nel
  pattern manifest puri queste vanno aggiunte esplicitamente quando
  serviranno.

### Neutral

- L'aumento di righe YAML rispetto al "chart con override values" e'
  modesto: ~100 righe contro ~30. Per un componente "core" come
  database, l'investimento di leggibilita' vale.

## Mitigations and re-evaluation

Per mitigare i rischi e definire criteri di re-valutazione:

1. **Eccezione documentata, non precedente**: questa decisione si
   applica solo a MongoDB. Per gli altri componenti di Fase 3 (Keycloak,
   Apisix) e Fase 4 (workload applicativi), si applicano:
   - Il driver "compatibilita' arm64" introdotto in questo ADR (verifica
     preventiva sistematica).
   - ADR-001 D8 (Kustomize con Helm generator) come default.
   - ADR-002 (override registry a `bitnamilegacy` per chart Bitnami
     non-deprecati e multi-arch).
   - Eccezioni motivate caso per caso, ognuna in un proprio ADR.

2. **Criterio di re-valutazione di MongoDB**: questa decisione viene
   riconsiderata se almeno uno dei seguenti accade:
   - L'Operator unificato MongoDB v1.x raggiunge stabilita' "production"
     dichiarata e diventa il pattern standard della community.
   - Il MongoDB Community Operator vecchio risolve le issue arm64
     (#1514, #1420) e diventa una scelta praticabile.
   - Il lab evolve verso scenari (es. multi-replica reale, sharding)
     dove il valore di un Operator diventa concreto.
   In tal caso, si scrivera' un ADR successivo che superseda questo
   sulla parte tattica MongoDB, mantenendo il driver arm64 introdotto
   qui.

3. **Driver arm64 — applicazione futura**: per ogni nuova decisione
   architetturale che coinvolga un chart, una immagine, o un componente,
   la conversazione di design include esplicitamente un check di
   compatibilita' arm64. Per chart Helm: verificare che le immagini
   referenziate (incluse quelle collaterali) abbiano manifest arm64.
   Per componenti compilati: verificare la presenza di binari/immagini
   arm64 ufficiali. La verifica e' parte del prompt di Code che
   precede l'esecuzione, non un follow-up.

## Riferimenti

- ADR-001 D8 (decisione originale su Kustomize + Helm generator):
  [`0001-strategia-gitops.md`](0001-strategia-gitops.md)
- ADR-002 (strategia registry post-deprecazione Bitnami):
  [`0002-strategia-registry-chart-helm.md`](0002-strategia-registry-chart-helm.md)
- Issue arm64 sull'Operator Community vecchio:
  https://github.com/mongodb/mongodb-kubernetes-operator/issues/1514
  https://github.com/mongodb/mongodb-kubernetes-operator/issues/1420
- Documentazione MongoDB Controllers for Kubernetes Operator (unificato):
  https://www.mongodb.com/docs/kubernetes/current/
- Immagine `mongo` ufficiale Docker Hub (multi-arch):
  https://hub.docker.com/_/mongo

## Storia

| Data | Stato | Note |
|---|---|---|
| 2026-05-01 | Accepted | Stesura iniziale, ratifica della scelta tra quattro alternative dopo identificazione del vincolo arm64. Introduzione del driver "compatibilita' arm64" come decision driver permanente per ADR successivi. |
| 2026-05-02 | Amended | Downgrade della versione MongoDB da 8.0 a 7.0. Al momento della costruzione di questo ambiente, MongoDB 8.x presentava un'incompatibilita' nota con il kernel Linux 6.19+ dovuta alla versione di TCMalloc vendorizzata (Shadow Stack/CET). Il kernel di OrbStack su Apple Silicon era 6.19.x, quindi MongoDB 8.x non parte. MongoDB 7.0 non e' affetto e funziona regolarmente. La scelta resta reversibile: quando MongoDB Inc. rilascera' una versione 8.x con TCMalloc patchato, sara' sufficiente cambiare il tag dell'immagine senza altre modifiche architetturali. Riferimento: https://www.mongodb.com/community/forums/t/mongodb-8-x-and-linux-kernel-6-19/337547 |
