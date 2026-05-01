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

| Tool | Versione | Note |
|---|---|---|
| OrbStack | latest | Container runtime su macOS, alternativa piu' efficiente di Docker Desktop su Apple Silicon |
| k3d | >= 5.7 | Wrapper per k3s in container Docker |
| kubectl | >= 1.30 | CLI Kubernetes |
| Helm | >= 3.15 | Package manager per Kubernetes |
| Homebrew | latest | Package manager macOS |

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
docker ps | grep k3d-registry
# atteso: container k3d-registry.localhost in esecuzione su porta 5000
```

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

*Da definire al prossimo step. L'idea e' bootstrappare ArgoCD con un
manifest diretto, poi farlo gestire da se' stesso (app-of-apps pattern), e
da li' deployare tutti i platform services come Application ArgoCD puntate
alle cartelle `platform/` di questo repo.*

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
```

Se il comando fallisce, avviare OrbStack dall'applicazione.

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

- [x] **Fase 1** — Cluster k3d con configurazione versionata
- [ ] **Fase 2** — Bootstrap ArgoCD + app-of-apps
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
