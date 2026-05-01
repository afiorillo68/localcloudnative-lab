# ADR-001 — Strategia GitOps per il laboratorio

## Status

Accepted — ratificato in conversazione architetturale del 1 maggio 2026.

## Context

Il progetto `localcloudnative-lab` ha l'obiettivo di fornire un ambiente
Kubernetes locale su Apple Silicon per prototipare e validare integrazioni
applicative end-to-end (FE + BE + DB) con use-case attesi che includono
sperimentazione su soluzioni GIS e applicativi AI/SLM. Il riferimento
architetturale di partenza e' lo stack del progetto DCPP - Tifoserie Web,
ma il laboratorio non mira al match 1:1 con quell'ambiente: l'obiettivo
e' un'architettura "comparable" cloud-native.

Questo ADR formalizza otto decisioni interdipendenti sulla strategia
GitOps adottata. Tutte le decisioni sono state prese consapevolmente,
non per inerzia su default; le motivazioni sono documentate sotto. Una
parte delle decisioni codifica scelte gia' implementate in fase di
scaffolding iniziale; l'altra parte introduce pattern nuovi, predisposti
ma non ancora attivati al momento della stesura.

## Decision drivers

- **Riproducibilita'**: chi clona il repo deve poter ricostruire l'ambiente
  da zero senza informazioni esterne.
- **Allineamento al target enterprise**: senza puntare al match 1:1 col
  cluster DCPP, mantenere comunque pattern coerenti con quelli usati in
  ambienti production-grade.
- **Velocita' di iterazione**: ottimizzazione per sperimentazione
  individuale su Mac, non per scalabilita' multi-developer.
- **Valore didattico**: il repo verra' pubblicato come progetto open su
  GitHub; le scelte devono essere comprensibili e replicabili da terzi.
- **Semplicita' operativa**: ogni componente aggiuntivo (controller,
  operator, CLI) deve avere un beneficio chiaro che giustifica la
  complessita' incrementale.

## Considered Options & Decisions

### D1 — Pattern di organizzazione delle Application Argo CD

**Decisione**: app-of-apps con directory recursive.

**Alternative considerate**:
- Application individuali singole (no parent app)
- ApplicationSet con generator

**Motivazione**:
Il pattern app-of-apps e' la formulazione canonica del bootstrap GitOps
con Argo CD. La variante con `directory` recursive (la root scansiona
una cartella e crea automaticamente Application per ogni file YAML
trovato) e' la piu' semplice tra quelle equivalenti per scopo, ed e'
sufficiente per un repo single-cluster con un numero contenuto di
Application (atteso: < 20).

ApplicationSet con generator e' superiore in scenari multi-cluster o
con pattern di replica complessi (es. "deploy questa Application su
tutti i cluster matchando un'etichetta"); per il nostro caso d'uso
sarebbe sovradimensionato. ApplicationSet e' pero' una superset di
app-of-apps, quindi l'eventuale migrazione futura non e' rotta.

**Conseguenze**:
- La root Application va applicata manualmente una sola volta in fase
  di bootstrap (`kubectl apply -n argocd -f gitops/applications/root-app.yaml`).
- Aggiungere una nuova Application al lab significa: aggiungere un file
  YAML in `gitops/applications/` e committare. Argo CD la sincronizza
  automaticamente.
- Rimuovere una Application: rimuovere il file da `gitops/applications/`,
  committare. La root applica `prune: true` e cancella la risorsa dal
  cluster.

### D2 — Strategia di repository

**Decisione**: mono-repo con boundary chiari per dominio.

**Alternative considerate**:
- Multi-repo (uno per platform, uno per workloads)

**Motivazione**:
Per un lab personale gestito da una sola persona, il costo di
coordinamento di un multi-repo (PR cross-repo, dependency bot, gestione
CI/CD distinta) supera il beneficio. Il mono-repo evita anche la
frammentazione della pubblicazione su GitHub: un solo URL didattico,
clonabile in un comando.

I "boundary chiari" sono garantiti dalla struttura cartelle: `platform/`
per i componenti di piattaforma, `gitops/` per le Application Argo CD,
`workloads/` per i microservizi e frontend (predisposta in vista di
Fase 4). La separazione e' visiva e organizzativa, non tecnologica.

**Disallineamento col target DCPP**: in DCPP la separazione platform vs
applicazioni e' a livello di repo GitLab distinti. Lo accettiamo
consapevolmente come differenza inerente alla scala.

**Conseguenze**:
- Una eventuale separazione futura (es. estrazione di un workload in
  repo dedicato) e' fattibile in mezz'ora con `git filter-repo`.
- Quando il repo diventera' multi-contributor, valutare l'introduzione
  di `CODEOWNERS` per esplicitare la separazione di responsabilita'.

### D3 — Self-management di Argo CD

**Decisione**: Argo CD gestisce se' stesso tramite una Application figlia
del pattern app-of-apps.

**Alternative considerate**:
- Argo CD esterno al pattern (gestito a mano via `kubectl apply -k`)
- Cluster di management dedicato (pattern enterprise)

**Motivazione**:
Il self-management e' il pattern raccomandato dalla documentazione
ufficiale di Argo CD per setup standalone. Permette di aggiornare
Argo CD stesso (versione, ConfigMap, RBAC) tramite il normale flusso
GitOps, senza eccezioni operative.

Il rischio teorico ("Argo CD si rompe sincronizzando una versione
buggata di se' stesso") e' mitigato da `prune: false` sulla Application
self-managed (Argo CD non puo' cancellare risorse di se' stesso) e da
`ServerSideApply: true` (necessario per CRD di grandi dimensioni).

Il pattern enterprise del cluster di management dedicato e' la risposta
"corretta" al rischio, ma richiede risorse (un secondo cluster) e
complessita' (networking inter-cluster, RBAC distinto) sproporzionate
per un lab personale. La scelta e' consapevole: in un contesto
production-grade (es. un eventuale lab "v2.0" che simulasse il modello
DCPP a tre cluster), questa decisione si rivisita.

**Conseguenze**:
- Modifiche a Argo CD passano per `git push` e si applicano via GitOps.
- Se un commit malformato rompe Argo CD, il recovery richiede
  `kubectl apply -k platform/argocd/` manuale (procedura di rescue
  documentata nel README).

### D4 — Naming dei namespace

**Decisione**: namespace `platform-<componente>` per i componenti di
piattaforma. Eccezione: `argocd` mantiene il nome convenzionale upstream.

**Alternative considerate**:
- Namespace omonimi al componente (`keycloak`, `apisix`, `mongodb`)
- Namespace condiviso `platform` per tutti i componenti

**Motivazione**:
Il prefisso `platform-` disambigua i namespace di piattaforma da quelli
applicativi futuri (`workloads/`). Evita collisioni quando un microservizio
si chiamera' "auth-service" o "keycloak-integration": il namespace di
quel servizio non rischia di sovrapporsi al namespace di Keycloak.

L'eccezione su `argocd` e' guidata dalla convenzione dell'ecosistema
upstream: tutta la documentazione, gli esempi, gli script di Argo CD
assumono quel nome. Rinominarlo introdurrebbe una frizione ricorrente
ogni volta che si consulta la documentazione, senza beneficio reale.

**Conseguenze**:
- Le Application Argo CD per i componenti di piattaforma hanno
  `destination.namespace: platform-<componente>`.
- I namespace vengono creati automaticamente con `CreateNamespace=true`
  alla prima sync.
- Per i workloads applicativi (Fase 4+), il pattern di naming sara'
  diverso (probabilmente `workloads-<dominio>` o simile, da decidere
  in Fase 4).

### D5 — Strategia di pinning della revisione Git

**Decisione**: `targetRevision: HEAD` per tutte le Application.

**Alternative considerate**:
- Pinning a tag versionati (es. `v1.0.0`)
- Pinning a SHA specifico

**Motivazione**:
In fase di laboratorio, la velocita' di iterazione prevale sulla
riproducibilita' storica. `HEAD` significa che ogni `git push` propaga
le modifiche al cluster al ciclo di sync successivo (default: 3 minuti).
Per un lab dove l'unico utilizzatore e' lo sviluppatore stesso, e'
ottimale.

Il pinning a tag o SHA e' superiore in scenari production-like dove
serve audit trail puntuale ("quale versione era deployata alle 14:00 di
ieri?") o in pipeline CI/CD che generano deployment automatici. Per
arrivarci servirebbe prima introdurre ambienti multipli (D6) e una
strategia di promotion via Git, oggi non rilevanti.

**Conseguenze**:
- Ogni commit su `main` puo' impattare il cluster entro pochi minuti.
- Un eventuale rollback richiede `git revert` + push.
- Quando in futuro verra' attivato un secondo ambiente (D6), questa
  decisione si rivedra': l'ambiente "stable" probabilmente passera' a
  pinning di tag, mentre `dev` restera' su `HEAD`.

### D6 — Strategia di ambienti

**Decisione**: struttura Kustomize `base + overlays/dev` predisposta per
ambienti multipli, ma attivato solo `dev` al momento della stesura.
Runbook per attivazione documentato in `docs/how-to/add-environment.md`.

**Alternative considerate**:
- Single-environment puro (nessun overlay)
- Multi-namespace simulato fin da subito (overlay `dev` + `stage` attivi)
- Multi-cluster simulato fin da subito (k3d con piu' cluster)

**Motivazione**:
La predisposizione "vuota ma pronta" e' una via di mezzo tra "non si fa"
e "si fa in pieno". Permette di:
- Esercitare il pattern Kustomize multi-overlay come sarebbe in un
  contesto enterprise, anche con un solo overlay attivo.
- Aggiungere un secondo ambiente (es. per testare modelli AI/SLM in
  isolamento) come diff incrementale, non come refactor.
- Mostrare ai lettori del repo come la struttura *dovrebbe* apparire
  in scenari multi-ambiente, anche se non li abbiamo (ancora) attivati.

Le alternative "fin da subito multi-X" sono state scartate per costo
di risorse: Mac con 16-24 GB di RAM non regge bene un Keycloak duplicato
o due cluster k3d simultanei.

**Conseguenze**:
- Le Application Argo CD puntano a `platform/<componente>/overlays/dev`.
- Aggiungere un ambiente significa creare un nuovo overlay e una nuova
  Application Argo CD (procedura nel runbook).
- Esiste un "rischio di predisposizione fantasma": cartelle vuote che
  invecchiano nel repo se nessun secondo ambiente viene mai attivato.
  Mitigazione: il runbook documenta cosa fare se si attiva, e se non
  si attiva la struttura non costa nulla mantenerla.

### D7 — Gestione segreti

**Decisione**: Sealed Secrets (Bitnami) come pattern primario per la
gestione segreti committati nel repo.

**Alternative considerate**:
- Segreti fuori dal Git, applicati a mano via `kubectl create secret`
- Repo Git separato privato per i segreti
- SOPS + age (cifratura a livello di file)
- External Secrets Operator + backend esterno (es. Vault)

**Motivazione**:
Sealed Secrets bilancia leggibilita', autosufficienza del repo e
complessita' operativa:
- Tutto il necessario per riprodurre l'ambiente vive nel repo (i segreti
  cifrati sono sicuri da committare, anche su repo pubblico).
- Il pattern e' familiare a chiunque conosca Kubernetes (controller +
  CRD `SealedSecret`).
- Il costo aggiuntivo e' basso (un controller in piu', una CLI
  `kubeseal` da installare localmente).

Le alternative scartate:
- Secret a mano: rompe GitOps.
- Repo separato privato: rompe l'autosufficienza didattica del repo
  pubblico.
- SOPS + age: superiore per controllo granulare, ma piu' complesso da
  setuppare e meno comprensibile per chi clona il repo per la prima
  volta.
- External Secrets + Vault: pattern enterprise, sproporzionato per un
  lab. Resta candidato per una eventuale evoluzione futura.

**Conseguenze**:
- Il Sealed Secrets controller dev'essere installato come prima cosa
  in Fase 3, prima dei componenti che hanno bisogno di segreti
  (Keycloak, MongoDB).
- La chiave master del controller dev'essere esportata e backuppata
  fuori dal repo (es. password manager personale). Senza, una
  distruzione del cluster k3d rende illeggibili tutti i segreti
  committati.
- La CLI `kubeseal` va aggiunta ai prerequisiti del README quando il
  controller verra' installato.
- Procedura di rotazione della chiave master: documentata nel runbook
  di Fase 3.

### D8 — Tecnologia di gestione manifest per i componenti

**Decisione**: Kustomize con Helm come generator (`helmCharts`).

**Alternative considerate**:
- Kustomize "puro" con manifest scritti a mano
- Helm "puro" con Argo CD configurato per gestire chart direttamente

**Motivazione**:
La struttura `base + overlays/dev` decisa in D6 implica gia' un layer
Kustomize. La domanda e' quale contenuto ci mettiamo dentro la `base/`.

- Kustomize puro implicherebbe scrivere a mano i Deployment, Service,
  ConfigMap, RBAC dei tre componenti — lavoro enorme che duplicherebbe
  cio' che la community ha gia' codificato nei chart Helm upstream.
- Helm puro romperebbe la struttura `base + overlays`: Argo CD nativo
  non mescola Helm e Kustomize, costringerebbe a un secondo refactor
  o a far convivere due pattern diversi nello stesso repo.
- Kustomize con Helm come generator (construct `helmCharts`) e' la
  combinazione naturalmente coerente: sfrutta i chart upstream e
  mantiene la struttura predisposta in D6.

**Conseguenze**:
- Argo CD richiede l'opzione `kustomize.buildOptions: --enable-helm`
  nel ConfigMap `argocd-cm`. La patch va aggiunta a
  `platform/argocd/argocd-cm-patch.yaml` prima del primo deploy di Fase 3.
- Le `base/kustomization.yaml` faranno reference a chart Helm pinnati
  per versione (no `latest`). I valori comuni vivono in `values-common.yaml`
  nella `base/`.
- Gli overlay sovrascrivono valori specifici via `values-<env>.yaml` o
  via patch Kustomize.
- La cache dei chart Helm scaricati e' gestita da Argo CD; eventuali
  problemi di rete in fase di sync sono diagnosticabili tramite log
  del repo-server.

## Decisioni implicite e da prendere in futuro

Le seguenti decisioni emergeranno in fasi successive e non sono coperte
da questo ADR. Saranno oggetto di ADR successivi (ADR-002, ADR-003...):

- **Strategia di CI/CD per i workloads applicativi** (build immagini,
  promozione tra ambienti, rollback).
- **Naming convention per i namespace dei workloads** (D4 copre solo
  la piattaforma).
- **Pattern di osservabilita'** (logging, metrics, tracing): se e quando
  introdurre Loki/Grafana/Tempo/Mimir come nel target DCPP.
- **Strategia di backup e disaster recovery del cluster k3d** (oltre al
  backup della chiave Sealed Secrets).
- **Eventuale evoluzione a pattern multi-cluster** (es. management
  dedicato come in DCPP) per fasi avanzate del laboratorio.

## Riferimenti

- Documentazione Argo CD app-of-apps:
  https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/
- Documentazione Sealed Secrets:
  https://github.com/bitnami-labs/sealed-secrets
- Documentazione Kustomize helmCharts:
  https://kubectl.docs.kubernetes.io/references/kustomize/builtins/#_helmchartinflationgenerator_
- Pattern MADR per Architectural Decision Records:
  https://adr.github.io/madr/
- Documento di architettura DCPP - Tifoserie Web v1.8 (interno).

## Storia

| Data | Stato | Note |
|---|---|---|
| 2026-05-01 | Accepted | Stesura iniziale, ratifica delle 8 decisioni |
