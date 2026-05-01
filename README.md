# localcloudnative-lab

Ambiente Kubernetes locale su Apple Silicon (M-series) per prototipare, testare
e validare uno stack cloud-native funzionalmente isomorfo a quello di un
ambiente enterprise on-premise. Riferimento d'origine: il progetto **DCPP -
Tifoserie Web** (Direzione Centrale Polizia di Prevenzione, Ministero
dell'Interno), ma il laboratorio e' generalizzabile a qualunque stack cloud
native con la stessa topologia di componenti.

L'obiettivo non e' simulare un cluster di produzione (impossibile su un
portatile), ma disporre di un ambiente in cui:

- validare manifest Kubernetes e chart Helm prima del porting su cluster reali;
- prototipare integrazioni applicative (OIDC con Keycloak, routing via Apisix,
  persistenza MongoDB, ricerca OpenSearch);
- testare flussi GitOps con ArgoCD;
- esercitarsi su pattern operativi (rolling update, rollback, observability)
  senza impattare ambienti reali.

## Convenzione di naming

| Elemento | Valore |
|---|---|
| Repository / cartella progetto | `localcloudnative-lab` |
| Cluster k3d | `lcn-lab` |
| Context kubectl | `k3d-lcn-lab` (prefisso `k3d-` aggiunto automaticamente) |
| Registry locale | `k3d-registry.localhost:5000` |
| `gitops/applications/` | Application CR di Argo CD (definizioni dichiarative GitOps) |
| `workloads/` | Microservizi e frontend applicativi (Fase 4+, attualmente non popolato) |
| Namespace componenti di piattaforma | Prefisso `platform-` (es. `platform-keycloak`, `platform-apisix`, `platform-mongodb`) per disambiguare dai namespace applicativi futuri (`workloads/`). Eccezione: `argocd` mantiene il nome convenzionale dell'ecosistema upstream. |
| Struttura Kustomize componenti | `platform/<componente>/base/` + `platform/<componente>/overlays/<env>/` — pattern base+overlays predisposto per ambienti multipli; attualmente solo `dev` e' definito. |

## Indice

1. [Architettura locale e mappatura al target](#architettura-locale-e-mappatura-al-target)
2. [Prerequisiti](#prerequisiti)
3. [Fase 1 — Cluster Kubernetes locale](#fase-1--cluster-kubernetes-locale)
4. [Fase 2 — GitOps con ArgoCD](#fase-2--gitops-con-argocd) *(prossimo step)*
5. [Fase 3 — Platform services (Keycloak, Apisix, MongoDB)](#fase-3--platform-services) *(da fare)*
6. [Fase 4 — Applicazioni demo (Spring Boot + Angular)](#fase-4--applicazioni-demo) *(da fare)*
7. [Troubleshooting](#troubleshooting)
8. [How-to: aggiungere un nuovo ambiente](docs/how-to/add-environment.md)

---

## Architettura locale e mappatura al target

| Componente target enterprise | Equivalente locale | Note |
|---|---|---|
| Nutanix NKP (Kubernetes) | k3d (k3s in container) | Stesso K8s upstream, scala diversa |
| containerd | containerd dentro k3s | Identico |
| Cilium CNI | Flannel (default k3s) | Per dev non serve eBPF |
| MetalLB | LoadBalancer integrato di k3d | Funzione equivalente |
| Apache Apisix | Apache Apisix (chart Helm) | Identico |
| Keycloak | Keycloak (chart Helm) | Identico |
| MongoDB Community | MongoDB (chart Bitnami) | Identico |
| OpenSearch | OpenSearch (chart) | Identico, pesante: on-demand |
| Harbor | Registry integrato di k3d | Sufficiente per dev |
| Nutanix Objects (S3) | MinIO | API S3-compatibile |
| GitLab + ArgoCD + Kargo | GitHub + ArgoCD locale | GitLab self-hosted troppo pesante |
| Grafana/Loki/Mimir/Tempo | kube-prometheus-stack + Loki | Versione leggera |

**Cosa NON viene replicato e perche':**

- **Air-gapping**: il target di riferimento DCPP e' air-gapped permanente;
  localmente abbiamo internet, lo usiamo per scaricare immagini e chart. Lo
  stack si comporta in modo diverso solo nei flussi di sincronizzazione
  (Hauler Registry, git bundle), che non e' interessante riprodurre in
  laboratorio.
- **Multi-nodo / HA**: k3d supporta multi-nodo simulati ma sempre sullo
  stesso host fisico. Non testeremo failover reale, scheduling cross-AZ,
  network partition.
- **Database-as-a-Service (Nutanix NDB)**: sul target i database sono erogati
  come servizio gestito. Localmente li installiamo come pod nel cluster,
  accettando il disallineamento sul deployment model (le interfacce
  applicative restano identiche).

Le decisioni architetturali rilevanti del progetto sono documentate
come ADR (Architectural Decision Records) in [`docs/adr/`](docs/adr/).
L'[ADR-001](docs/adr/0001-strategia-gitops.md) raccoglie le otto decisioni
interdipendenti sulla strategia GitOps adottata.

Il processo decisionale che ha portato a queste scelte e' descritto
in [`docs/methodology.md`](docs/methodology.md): un documento
metodologico che racconta il pattern di lavoro adottato (Architect +
Engineer + Decisore con strumenti AI) sia in astratto sia con esempi
concreti tratti dallo sviluppo di questo progetto.

## Prerequisiti

### Hardware

- Mac con Apple Silicon (M1/M2/M3/M4)
- **16 GB RAM minimo** — sufficiente se non si accendono tutti i servizi
  contemporaneamente
- **24 GB RAM consigliato** — comodo per tenere su tutto lo stack
- 30+ GB di spazio disco libero (immagini container + volumi PV)

### Software

| Tool | Versione minima | Versione testata | Note |
|---|---|---|---|
| OrbStack | latest | 2.1.1 (20026) | Container runtime su macOS, alternativa piu' efficiente di Docker Desktop su Apple Silicon |
| k3d | >= 5.7 | 5.8.3 | Wrapper per k3s in container Docker |
| kubectl | >= 1.30 | 1.36.0 | CLI Kubernetes |
| Helm | >= 3.15 | 4.1.4 | Package manager per Kubernetes |
| Homebrew | latest | 5.1.8 | Package manager macOS |

> **Nota su OrbStack vs Docker Desktop**: OrbStack e' la scelta preferibile
> su Apple Silicon. Consuma circa la meta' della RAM di Docker Desktop e ha
> performance migliori con i volumi. E' gratuito per uso personale; per uso
> commerciale ha una licenza. In alternativa, Colima e' gratuito e
> open-source ma con UX piu' spartana. Docker Desktop resta valido se gia'
> lo si usa per altro.

### Installazione prerequisiti

```bash
# OrbStack (consigliato)
brew install orbstack

# Tooling Kubernetes
brew install k3d kubectl helm
```

Verifica:

```bash
orb version
k3d version
kubectl version --client
helm version
```

Avvia OrbStack almeno una volta dall'app per completare il setup.

> **Nota operativa — Docker socket con OrbStack**: OrbStack espone il daemon
> Docker su `~/.orbstack/run/docker.sock` (non su `/var/run/docker.sock`).
> Questo e' trasparente per i tool che usano il context Docker corrente, ma
> se si invoca `k3d` da una shell che non eredita il context OrbStack (es.
> script CI, sessioni tmux fresche) occorre impostare esplicitamente
> `DOCKER_HOST=unix://${HOME}/.orbstack/run/docker.sock` oppure assicurarsi
> che `~/.orbstack/bin` sia nel PATH (OrbStack lo aggiunge al login shell).
> I binari Docker di OrbStack si trovano in `~/.orbstack/bin/`.

## Fase 1 — Cluster Kubernetes locale

### Obiettivo

Creare un cluster Kubernetes locale a singolo nodo con `k3d`, esposto su
porte HTTP/HTTPS standard, pronto per ospitare ArgoCD e i platform services
nelle fasi successive.

### Decisioni di design

- **Single-node** in Fase 1. Multi-nodo simulato non aggiunge valore in dev
  e raddoppia il consumo di RAM. Lo abiliteremo solo se ci servira' per
  testare affinity/anti-affinity rules.
- **Server K3s con Traefik DISABILITATO**. K3s installa Traefik come ingress
  controller di default; lo disabilitiamo perche' useremo **Apache Apisix**
  come gateway, coerente col target enterprise.
- **Disabilitato anche servicelb (klipper-lb)**. k3d gestisce l'esposizione
  dei service LoadBalancer tramite il proprio loadbalancer container, non
  serve il servicelb interno di K3s.
- **Port-mapping 80 e 443** sul loadbalancer di k3d, cosi' le app esposte
  via Apisix saranno raggiungibili da `http://localhost` senza port-forward
  manuali.
- **Registry locale integrato** (`k3d-registry.localhost:5000`) per spingere
  immagini buildate localmente senza passare da Docker Hub. Sostituisce
  Harbor per la fase di sviluppo.

### File di configurazione

Il cluster e' definito in modo dichiarativo in
[`cluster/k3d-cluster.yaml`](cluster/k3d-cluster.yaml). Tutti i parametri
sono versionati: per ricreare il cluster da zero basta rilanciare il
comando `k3d cluster create --config`.

### Creazione del cluster

```bash
# Dalla root del repo
k3d cluster create --config cluster/k3d-cluster.yaml
```

Tempo di creazione: ~30-60 secondi sulla prima esecuzione (download
immagini), ~15 secondi sulle successive.

### Verifica

```bash
# Il context kubectl viene impostato automaticamente da k3d
kubectl config current-context
# atteso: k3d-lcn-lab

# Nodi
kubectl get nodes
# atteso: 1 nodo "Ready", role control-plane,master

# Pod di sistema
kubectl get pods -A
# attesi: coredns, local-path-provisioner, metrics-server in stato Running
# NON deve apparire traefik (l'abbiamo disabilitato)

# Registry locale
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep registry
# atteso: container registry.localhost in esecuzione su porta 5000
# Nota: il nome del container e' "registry.localhost" (non "k3d-registry.localhost")
# come definito in cluster/k3d-cluster.yaml → registries.create.name
```

> **Nota operativa — nome container registry**: il container della registry
> locale si chiama `registry.localhost` (non `k3d-registry.localhost`).
> Il naming e' determinato dal campo `registries.create.name` nel file
> `cluster/k3d-cluster.yaml`. L'hostname da usare nei tag delle immagini
> resta `k3d-registry.localhost:5000` perche' k3d aggiunge automaticamente
> un alias DNS nel network `k3d-lcn-lab`.

### Test di sanity

Deploy di un nginx di prova per verificare che pod, service e port-mapping
funzionino:

```bash
kubectl create deployment sanity-nginx --image=nginx:alpine
kubectl expose deployment sanity-nginx --port=80 --type=ClusterIP
kubectl port-forward svc/sanity-nginx 8080:80
# In un altro terminale:
curl http://localhost:8080
# atteso: HTML "Welcome to nginx!"

# Cleanup
kubectl delete deployment sanity-nginx
kubectl delete svc sanity-nginx
```

### Reset / distruzione

```bash
# Stop del cluster (mantiene stato)
k3d cluster stop lcn-lab

# Start del cluster esistente
k3d cluster start lcn-lab

# Distruzione completa (cancella anche i volumi)
k3d cluster delete lcn-lab
```

---

## Fase 2 — GitOps con ArgoCD

### Obiettivo

Bootstrappare ArgoCD con il manifest versionato in questo repo, poi
farlo gestire da se' stesso (*app-of-apps pattern*), e da li' deployare
tutti i platform services come Application ArgoCD puntate alle cartelle
`platform/` di questo repo.

### File di configurazione

Tutto il necessario per installare e configurare ArgoCD e' in
`platform/argocd/`. Chiunque cloni il repo ottiene esattamente la stessa
installazione, senza dipendere da risorse esterne al momento del deploy.

```
platform/argocd/
├── install.yaml          # Manifest upstream ArgoCD v2.13.3 (vendorato)
├── kustomization.yaml    # Overlay: base=install.yaml + patch CM dev
└── argocd-cm-patch.yaml  # Patch ConfigMap: insecure mode, annotation tracking
```

**`install.yaml`** e' il manifest ufficiale ArgoCD scaricato una volta e
committato nel repo. Non viene scaricato a runtime: il bootstrap usa
solo file locali. Per aggiornare ArgoCD scaricare la nuova versione del
manifest, aggiornare `kustomization.yaml` e fare un push — ArgoCD si
aggiorna da solo al prossimo ciclo di sync.

**`kustomization.yaml`** combina base e patch in un unico apply atomico:
install e configurazione vengono applicate insieme, non in passi separati.

**`argocd-cm-patch.yaml`** imposta tre parametri per il laboratorio:

| Parametro | Valore | Motivo |
|---|---|---|
| `server.insecure` | `"true"` | Disabilita TLS proprio; TLS termination delegata ad Apisix (Fase 3) |
| `application.resourceTrackingMethod` | `annotation` | Piu' affidabile con Helm chart che hanno gia' le proprie label |
| `timeout.reconciliation` | `300s` | Margine per pull lente in lab |

### Pattern app-of-apps

```
gitops/applications/root-app.yaml   ← applicata una sola volta via kubectl (bootstrap)
        │
        ▼  ArgoCD sincronizza la directory gitops/applications/
   ┌────────────────────────────────────────────────────────┐
   │  gitops/applications/                                  │
   │  ├── argocd-app.yaml    → platform/argocd/            │ ArgoCD self-manages
   │  ├── keycloak-app.yaml  → platform/keycloak/   [F3]  │
   │  ├── apisix-app.yaml    → platform/apisix/     [F3]  │
   │  └── mongodb-app.yaml   → platform/mongodb/    [F3]  │
   └────────────────────────────────────────────────────────┘
```

La root Application e' l'unica risorsa applicata manualmente (una tantum).
Tutto il resto — incluso ArgoCD stesso — viene gestito via GitOps: ogni
`git push` al branch `main` si riflette nel cluster al ciclo successivo.

Le Application `[F3]` sono presenti nel repo ma prive di `syncPolicy.automated`:
non deployano nulla finche' le rispettive directory `platform/` non sono
popolate con chart Helm o manifest Kubernetes.

### Prerequisiti

- Cluster `lcn-lab` attivo (Fase 1 completata)
- `kubectl` nel PATH e context puntato a `k3d-lcn-lab`
- Repo pushato su GitHub (necessario per il flusso GitOps)
- Personal Access Token GitHub con scope `repo` (per repo privati)

### Bootstrap (una tantum, da eseguire dopo aver clonato il repo)

```bash
# Dalla root del repo
GH_TOKEN=<personal-access-token-github> \
  ./bootstrap/argocd-bootstrap.sh
```

Il script esegue in sequenza:

1. **Preflight**: verifica che `kubectl` punti a `k3d-lcn-lab` e che
   `platform/argocd/install.yaml` esista nel repo clonato.
2. **Namespace**: `kubectl create namespace argocd` (idempotente).
3. **Installazione**: `kubectl apply -k platform/argocd/` — unico comando
   che applica `install.yaml` + `argocd-cm-patch.yaml` in modo atomico.
4. **Attesa**: rollout status su `argocd-server`, `application-controller`,
   `repo-server`.
5. **Credenziali repo**: crea il Secret ArgoCD con il token GitHub per
   accedere al repo privato.
6. **Root Application**: applica `gitops/applications/root-app.yaml` — da questo momento
   ArgoCD gestisce se stesso e le Application figlie.
7. **Riepilogo**: stampa password admin, stato pod, stato Application.

Tempo atteso: ~2-3 minuti (pull immagini container alla prima esecuzione).

### Accesso UI

```bash
make argocd-ui
# Apri: https://localhost:8090
```

Il comando esegue i controlli preliminari (cluster raggiungibile, porta
8090 libera) e poi lancia `kubectl port-forward -n argocd svc/argocd-server
8090:443`. Premi `Ctrl-C` per chiudere il tunnel.

Il browser mostrera' un avviso sul certificato self-signed di ArgoCD:
clicca *Avanzate → Procedi comunque* (o equivalente). L'avviso e' normale e
non indica un problema di sicurezza nel contesto del laboratorio locale.

```bash
# Recupera la password admin iniziale
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode; echo
```

> **Nota — port-forward e ciclo di vita del processo**: il tunnel
> `kubectl port-forward` e' un processo che vive nella shell in cui e' stato
> lanciato. Se la shell viene chiusa, il Mac va in sleep o il processo viene
> interrotto, il tunnel cade silenziosamente. Il cluster non e' rotto:
> basta rilanciare `make argocd-ui`. Vedi anche la sezione
> [Troubleshooting](#troubleshooting).

> **Nota — evoluzione in Fase 3**: in Fase 3 Apisix sara' configurato come
> Ingress controller. La UI di Argo CD sara' esposta tramite un ApisixRoute
> su un hostname dedicato (es. `argocd.lcn-lab.local`), con TLS termination
> gestita da Apisix e senza necessita' di port-forward. Questo allinea il
> laboratorio al pattern enterprise target (gateway centralizzato per
> tutte le console di amministrazione).

### Verifica

```bash
# 1. Pod tutti Running
kubectl get pods -n argocd

# 2. CRD ArgoCD presenti (3: applications, applicationsets, appprojects)
kubectl get crd | grep argoproj

# 3. Applications sincronizzate
kubectl get applications -n argocd
# atteso: root, argocd, keycloak, apisix, mongodb — tutte Synced/Healthy

# 4. ArgoCD self-management: modifica argocd-cm-patch.yaml,
#    fai git push e osserva il sync automatico sul ConfigMap
kubectl get configmap argocd-cm -n argocd -o yaml | grep resourceTrackingMethod
# atteso: application.resourceTrackingMethod: annotation
```

> **Nota — warning `last-applied-configuration` su installazione esistente**:
> se si esegue `kubectl apply -k platform/argocd/` su un cluster in cui ArgoCD
> era stato installato in precedenza con `kubectl apply -f <url>` (senza
> kustomize), kubectl emette warning sulle annotation mancanti. Non e' un
> errore: le annotation vengono aggiunte automaticamente al primo apply e
> i warning non si ripresentano. Su un'installazione fresh (cluster nuovo)
> non compaiono.

### Aggiornare ArgoCD

```bash
# 1. Scarica il nuovo manifest
curl -fsSL https://raw.githubusercontent.com/argoproj/argo-cd/vX.Y.Z/manifests/install.yaml \
  -o platform/argocd/install.yaml

# 2. Aggiorna la versione in platform/argocd/kustomization.yaml
#    e in bootstrap/argocd-bootstrap.sh (variabile ARGOCD_VERSION)

# 3. Commit e push — ArgoCD si aggiorna da solo
git add platform/argocd/install.yaml platform/argocd/kustomization.yaml \
        bootstrap/argocd-bootstrap.sh
git commit -m "argocd: aggiorna a vX.Y.Z"
git push
```

### Componenti installati

| Componente | Versione | Note |
|---|---|---|
| argocd-server | v2.13.3 | HTTPS con cert self-signed; accesso via `make argocd-ui`; TLS termination via Apisix in Fase 3 |
| argocd-application-controller | v2.13.3 | StatefulSet, 1 replica |
| argocd-repo-server | v2.13.3 | Cache manifest Git |
| argocd-dex-server | v2.13.3 | OIDC broker; si integra con Keycloak in Fase 3 |
| argocd-redis | v2.13.3 | Cache interna |
| argocd-applicationset-controller | v2.13.3 | Per ApplicationSet (uso futuro) |
| argocd-notifications-controller | v2.13.3 | Non configurato in lab |

## Fase 3 — Platform services

*Keycloak, Apache Apisix, MongoDB. Configurazioni Helm minimali ma
realistiche per un dev environment, con realm Keycloak preconfigurato coi
ruoli applicativi del progetto DCPP (Operatore/Osservatore DCPP,
Operatore/Osservatore DIGOS provinciale e distrettuale).*

## Fase 4 — Applicazioni demo

*Microservizio Spring Boot di esempio (build multi-arch arm64), front-end
Angular, integrazione end-to-end Angular → Apisix → Spring Boot → MongoDB
con auth via Keycloak.*

---

## Troubleshooting

### La UI di Argo CD non risponde piu' dopo essere stata accessibile

**Sintomo**: `make argocd-ui` aveva funzionato, la UI era aperta nel browser,
poi ha smesso di rispondere (connessione rifiutata o timeout).

**Causa**: il `kubectl port-forward` e' un processo — non un servizio di
sistema. Vive solo finche' vive la shell in cui e' stato avviato. Se quella
shell viene chiusa, il Mac va in sleep, la sessione SSH scade, o il processo
kubectl viene interrotto per qualunque altra ragione, il tunnel cade
silenziosamente. Il cluster e' integro, i pod di Argo CD continuano a girare:
manca solo il canale di accesso locale.

**Soluzione**: rilanciare il tunnel.

```bash
make argocd-ui
```

Questo e' il comportamento normale del port-forward di Kubernetes e non
indica alcuna rottura del cluster o di Argo CD.

---

### `k3d cluster create` fallisce con errori di rete

Verificare che OrbStack/Docker sia avviato:

```bash
docker ps
# oppure, se il context non e' configurato:
~/.orbstack/bin/docker ps
```

Se il comando fallisce, avviare OrbStack dall'applicazione.

### `k3d` non trova il daemon Docker (`Cannot connect to Docker daemon`)

OrbStack espone il socket su `~/.orbstack/run/docker.sock`. In alcune
configurazioni di shell (es. tmux, login remoto) il context Docker potrebbe
non essere impostato. Soluzione:

```bash
export DOCKER_HOST=unix://${HOME}/.orbstack/run/docker.sock
k3d cluster create --config cluster/k3d-cluster.yaml
```

In alternativa, assicurarsi che la riga di inizializzazione OrbStack sia
presente nel proprio `.zshrc` / `.bashrc` (OrbStack la aggiunge al primo
avvio).

### Le porte 80/443 sono gia' occupate

Probabile conflitto con un web server locale. Alternativa: cambiare le
porte nel file `cluster/k3d-cluster.yaml` (es. 8080/8443) e accedere con
`http://localhost:8080`.

### Performance lente / ventole rumorose

Su 16 GB di RAM e' facile saturare. Suggerimenti:

- Tenere un solo cluster k3d attivo (`k3d cluster list`).
- Spegnere OpenSearch e lo stack monitoring quando non servono.
- Verificare il memory limit di OrbStack (Settings → Resources): impostarlo
  a ~10-12 GB su un Mac da 16 GB lascia margine al sistema.

### `kubectl` punta al cluster sbagliato

```bash
kubectl config get-contexts
kubectl config use-context k3d-lcn-lab
```

---

## Roadmap

- [x] **Fase 1** — Cluster k3d con configurazione versionata *(cluster `lcn-lab` attivo, verificato 2026-05-01)*
- [x] **Fase 2** — Bootstrap ArgoCD + app-of-apps *(ArgoCD v2.13.3 attivo, app-of-apps pronta per GitHub remote, verificato 2026-05-01)*
- [x] **Predisposizione struttura base + overlays/dev** *(Fase 3 ready — placeholder Kustomize per keycloak, apisix, mongodb)*
- [ ] **Fase 3** — Keycloak con realm preconfigurato
- [ ] **Fase 3** — Apache Apisix come gateway
- [ ] **Fase 3** — MongoDB Community
- [ ] **Fase 4** — Spring Boot demo service
- [ ] **Fase 4** — Front-end Angular demo
- [ ] **Fase 5** — OpenSearch + stack osservabilita' (opzionale, on-demand)
- [ ] **Fase 6** — MinIO come sostituto di Nutanix Objects
- [ ] Documentazione architetturale (`docs/architecture.md`)
- [ ] Pubblicazione su GitHub con licenza Apache-2.0

## Licenza

*Da definire in fase di pubblicazione su GitHub. Candidata: Apache-2.0
(piu' adatta per un progetto infrastrutturale che potrebbe contenere
riferimenti o snippet riconducibili al contesto enterprise).*
