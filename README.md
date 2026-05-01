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

## Indice

1. [Architettura locale e mappatura al target](#architettura-locale-e-mappatura-al-target)
2. [Prerequisiti](#prerequisiti)
3. [Fase 1 — Cluster Kubernetes locale](#fase-1--cluster-kubernetes-locale)
4. [Fase 2 — GitOps con ArgoCD](#fase-2--gitops-con-argocd) *(prossimo step)*
5. [Fase 3 — Platform services (Keycloak, Apisix, MongoDB)](#fase-3--platform-services) *(da fare)*
6. [Fase 4 — Applicazioni demo (Spring Boot + Angular)](#fase-4--applicazioni-demo) *(da fare)*
7. [Troubleshooting](#troubleshooting)

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

Bootstrappare ArgoCD con un manifest diretto, poi farlo gestire da se'
stesso (*app-of-apps pattern*), e da li' deployare tutti i platform services
come Application ArgoCD puntate alle cartelle `platform/` di questo repo.

### Architettura GitOps

```
Root Application (apps/root-app.yaml)   ← applicata una sola volta via kubectl
        │
        ▼  sincronizza la directory apps/
   ┌──────────────────────────────────────────────────┐
   │  apps/                                           │
   │  ├── argocd-app.yaml    → platform/argocd/      │ ArgoCD self-manages
   │  ├── keycloak-app.yaml  → platform/keycloak/    │ Fase 3
   │  ├── apisix-app.yaml    → platform/apisix/      │ Fase 3
   │  └── mongodb-app.yaml   → platform/mongodb/     │ Fase 3
   └──────────────────────────────────────────────────┘
```

Le Application di Fase 3 sono presenti nel repo ma non hanno ancora una
`syncPolicy.automated`: non provocano nulla finche' le directory
`platform/<servizio>/` non sono popolate.

### Prerequisiti

Cluster `lcn-lab` attivo (Fase 1). Il bootstrap script lo verifica
automaticamente.

### Bootstrap (una tantum)

```bash
# Dalla root del repo
./bootstrap/argocd-bootstrap.sh
```

Il script:
1. Crea il namespace `argocd`
2. Applica il manifest upstream ArgoCD v2.13.3
3. Patcha il ConfigMap per la modalita' dev (insecure, annotation tracking)
4. Attende che tutti i componenti siano `Running`
5. Stampa password admin e istruzioni di accesso

Tempo atteso: ~2-3 minuti (download immagini alla prima esecuzione).

### Accesso all'UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8090:80
# Apri: http://localhost:8090
# username: admin
# password: recupera con il comando sotto
```

```bash
# Recupera la password iniziale
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode; echo
```

> **Nota**: il server ArgoCD gira in modalita' `insecure` (no TLS proprio).
> Il port-forward su porta 80 reindirizza a 8080 interno. Usare
> `http://localhost:8090` (non https). Questo e' intenzionale per il lab:
> in Fase 3 Apisix fara' da reverse proxy con TLS termination.

### Attivazione root Application (richiede repo su GitHub)

Le Application CR in `apps/` usano `${REPO_URL}` come placeholder.
Per attivarle il repo deve essere pushato su un Git remote raggiungibile
da ArgoCD (GitHub, GitLab, Gitea, ecc.).

```bash
# 1. Pusha il repo su GitHub
git remote add origin https://github.com/OWNER/localcloudnative-lab.git
git push -u origin main

# 2. Applica la root Application (sostituisce ${REPO_URL})
REPO_URL=https://github.com/OWNER/localcloudnative-lab \
  envsubst < apps/root-app.yaml | kubectl apply -n argocd -f -

# 3. Verifica sincronizzazione
kubectl get applications -n argocd
```

Dopo questo passaggio ArgoCD gestira' se stesso e le Application figlie
tramite GitOps: ogni `git push` al branch main si riflettera' nel cluster.

### Verifica post-bootstrap

```bash
# Tutti i pod argocd in Running
kubectl get pods -n argocd

# CRD ArgoCD installate
kubectl get crd | grep argoproj

# Application (solo se root-app e' stata applicata)
kubectl get applications -n argocd
```

### Componenti installati

| Componente | Versione | Note |
|---|---|---|
| ArgoCD | v2.13.3 | Install manifest standard (non HA) |
| argocd-application-controller | — | StatefulSet, 1 replica |
| argocd-server | — | Modalita' insecure per lab |
| argocd-repo-server | — | — |
| argocd-dex-server | — | OIDC integration (per Fase 3 con Keycloak) |
| argocd-redis | — | Cache interna |
| argocd-applicationset-controller | — | Per ApplicationSet in futuro |
| argocd-notifications-controller | — | Notifiche (non configurato in lab) |

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
