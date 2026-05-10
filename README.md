# localcloudnative-lab

A local Kubernetes lab on Apple Silicon for prototyping cloud-native
stacks end-to-end, with rigorous architectural documentation and a
pattern for working with AI tools as collaborators rather than
oracles.

## Why this exists

I needed a place to validate manifests, Helm charts, and operational
patterns before pushing them to real clusters. The reference target
is an enterprise on-premise stack (Nutanix HCI, NKP, air-gapped, the
works), but the lab is generalizable to any cloud-native stack with a
similar topology.

The constraints are real:

- **Apple Silicon arm64**, which rules out a surprising number of
  charts and images that still ship amd64-only.
- **Single laptop**, so no real HA, no realistic failover, no
  cross-AZ scheduling tests.
- **Personal lab budget**, which means open-source tooling and no
  commercial subscriptions.

What this *is* good for: validating manifests, prototyping
integrations (OIDC with Keycloak, routing via Apisix, MongoDB
persistence, OpenSearch), exercising GitOps flows with Argo CD, and
practicing operational patterns (rolling updates, rollbacks,
observability) without touching real environments.

What this *isn't*: a substitute for a production cluster, a
performance benchmark, or a tutorial. It's a working lab with
honest documentation about the trade-offs.

## What's interesting here

Beyond the lab itself, three things in this repo might be worth
your time:

- **Architectural Decision Records** in [`docs/adr/`](docs/adr/),
  documenting the choices made and the alternatives considered. ADR-001
  is an omnibus ratifying eight interlocking GitOps decisions; ADR-002
  handles the post-Bitnami-deprecation registry strategy; ADR-003 is
  the platform-aware exception for MongoDB on arm64 plus the new
  decision driver this introduced.
- **A working methodology** for collaborating with generative AI tools
  in [`docs/methodology.md`](docs/methodology.md): the
  Architect + Engineer + Decision-maker pattern, written both in the
  abstract and as a case study with episodes from this project,
  including the ones where the pattern broke.
- **Operational runbooks** in [`docs/how-to/`](docs/how-to/), tested
  against the actual lab and updated when reality required it.

## What's inside (current state)

| Component | Status | Notes |
|---|---|---|
| k3d cluster | Running | Single-node, Traefik disabled, port 80/443 mapped |
| Argo CD v2.13.3 | Healthy | Self-managed via app-of-apps, accessible via `make argocd-ui` |
| Sealed Secrets v0.36.6 | Healthy | Master key backed up in Bitwarden + Keychain |
| MongoDB 7.0 | Healthy | Replica set rs0, single replica, pure Kustomize manifests (see ADR-003) |
| Keycloak 26 | Healthy | Bitnami chart with PostgreSQL subchart, realm `lcn` imported, accessible via `make keycloak-ui` |
| Apache Apisix 3.16.0 | Healthy | Standalone etcd backend (ADR-004), TLS edge termination via ApisixRoute (ADR-005) |
| OpenSearch | Planned | Phase 5 — search and observability stack |
| MinIO | Planned | Phase 6 — S3-compatible object storage |

**Phase 3 closed**: 5 ADRs ratified, 13 methodology lessons accumulated,
disaster recovery procedure validated end-to-end via cluster reset and
SealedSecret master key restore.

## Demo applications

The platform hosts companion demo applications that exercise the
end-to-end stack. Each demo is published in its own repository:

- **[lcnpages-app](https://github.com/afiorillo68/lcnpages-app)** —
  a Notion-like knowledge base demonstrating Spring Boot 4 + Angular 21,
  MongoDB document storage, OIDC federation via Keycloak, and TLS
  termination via Apisix. **Status**: scaffolding complete (Phase 4
  Step 1A), Keycloak client and test user verified end-to-end (Phase
  4 Step 1B), backend and frontend implementation in progress.

Additional demos will be added as Phase 4 progresses, designed to
exercise different facets of the platform (object storage,
observability, AI/SLM workloads).

## Quick start

### Prerequisites

- Apple Silicon Mac (M1/M2/M3/M4) with **16 GB RAM** minimum (24 GB
  recommended)
- 30+ GB free disk space
- [OrbStack](https://orbstack.dev/) (recommended over Docker Desktop
  on Apple Silicon — about half the RAM consumption)
- `k3d` (>= 5.7), `kubectl` (>= 1.30), `helm` (>= 3.15), `kubeseal`
  (>= 0.27)

```bash
brew install orbstack k3d kubectl helm kubeseal
```

### Clone and bootstrap

```bash
git clone https://github.com/afiorillo68/localcloudnative-lab.git
cd localcloudnative-lab

# Phase 1 — create the k3d cluster
k3d cluster create --config cluster/k3d-cluster.yaml

# Phase 2 — bootstrap Argo CD (one-time)
GH_TOKEN=<your-github-personal-access-token> ./bootstrap/argocd-bootstrap.sh

# Phase 3 — Sealed Secrets and MongoDB are deployed automatically
# by Argo CD once the bootstrap is done. SealedSecret credentials
# need to be generated locally with kubeseal — see
# docs/how-to/sealed-secrets-operations.md
```

Total time on a fresh laptop: about 5 minutes for Phase 1+2, plus
manual time for SealedSecret generation in Phase 3.

### Daily operations

The lab is designed to be turned on and off as needed. Idle k3d
containers consume nothing; running components draw about 450 MB of
RAM at rest (rising to ~1 GB under active use).

| Command | What it does |
|---|---|
| `make lab-up` | Start the cluster and wait for critical components to be ready |
| `make lab-down` | Stop the cluster (OrbStack stays running, stop manually if desired) |
| `make lab-status` | Show current state without modifying anything |
| `make argocd-ui` | Port-forward and instructions for the Argo CD UI |
| `make keycloak-ui` | Port-forward and instructions for the Keycloak UI |

All commands are idempotent and safe to re-run.

## Repository structure

```
localcloudnative-lab/
├── cluster/                     k3d cluster definition (declarative)
├── bootstrap/                   one-time bootstrap script for Argo CD
├── platform/                    platform components (Argo CD, Sealed Secrets, MongoDB, ...)
│   └── <component>/
│       ├── base/                Kustomize base — shared definitions
│       └── overlays/dev/        environment-specific overlay (more envs to come)
├── gitops/applications/         Argo CD Application CRs (one per platform component)
├── workloads/                   application workloads (Phase 4+, currently empty)
└── docs/
    ├── adr/                     Architectural Decision Records (MADR format)
    ├── how-to/                  operational runbooks
    └── methodology.md           the Architect+Engineer+Decision-maker pattern
```

Detailed setup walkthroughs for Phase 1 and Phase 2 live in
[`docs/setup/`](docs/setup/).

## Naming conventions

| Element | Value |
|---|---|
| Repository / project folder | `localcloudnative-lab` |
| k3d cluster | `lcn-lab` |
| kubectl context | `k3d-lcn-lab` (k3d adds the prefix automatically) |
| Local registry | `k3d-registry.localhost:5000` |
| Platform component namespaces | `platform-<component>` (e.g., `platform-mongodb`). Exception: `argocd` keeps the upstream ecosystem name. |
| Kustomize structure | `platform/<component>/base/` + `platform/<component>/overlays/<env>/` — base+overlays pattern, currently only `dev` is defined |

## Architecture and design decisions

The relevant architectural decisions are documented as ADRs in
[`docs/adr/`](docs/adr/). Highlights:

- **[ADR-001](docs/adr/0001-strategia-gitops.md)** — eight
  interlocking decisions on GitOps strategy: app-of-apps with
  directory recursive, mono-repo with clear boundaries, self-managed
  Argo CD, namespace conventions, base+overlays Kustomize structure,
  Sealed Secrets for credentials, Kustomize with Helm as generator.
- **[ADR-002](docs/adr/0002-strategia-registry-chart-helm.md)** —
  registry strategy after the Bitnami deprecation of August 2025.
  Trade-offs and the pragmatic choice of `bitnamilegacy` for the
  components where it works.
- **[ADR-003](docs/adr/0003-eccezione-mongodb-arm64.md)** — the
  MongoDB exception. Pure Kustomize manifests instead of Helm chart
  because no Bitnami chart provides arm64 images. Introduces a new
  permanent decision driver: arm64 compatibility verified before
  every architectural ratification.
- **[ADR-004](docs/adr/0004-apisix-etcd-standalone.md)** — Apisix
  etcd standalone instead of Bitnami subchart, to work around an
  Argo CD PreSync hook deadlock.
- **[ADR-005](docs/adr/0005-apisix-tls-edge-termination.md)** — TLS
  edge termination pattern with Apisix, including documented
  backend-specific quirks for Argo CD and Keycloak that any future
  workload behind Apisix will need to know about.

Decisions identified but not yet ratified live in
[`docs/adr/BACKLOG.md`](docs/adr/BACKLOG.md). Open architectural
questions are surfaced there before they become technical debt.

## Mapping to the enterprise target

This lab mirrors the topology of an enterprise on-premise stack
without trying to reproduce its scale. The components map roughly as
follows:

| Enterprise target component | Local equivalent | Notes |
|---|---|---|
| Nutanix NKP (Kubernetes) | k3d (k3s in containers) | Same upstream Kubernetes, different scale |
| containerd | containerd inside k3s | Identical |
| Cilium CNI | Flannel (k3s default) | eBPF features not needed for dev |
| MetalLB | k3d's built-in load balancer | Equivalent function |
| Apache Apisix | Apache Apisix (Helm chart) | Identical |
| Keycloak | Keycloak (Helm chart) | Identical |
| MongoDB Community | MongoDB 7.0 (pure manifests, multi-arch image) | Identical at the protocol level |
| Harbor | k3d's integrated registry | Sufficient for dev |
| Nutanix Objects (S3) | MinIO | S3-compatible API |
| GitLab + Argo CD + Kargo | GitHub + local Argo CD | Self-hosted GitLab is too heavy |
| Vault / GitOps secrets | Sealed Secrets (Bitnami) | Encrypted CRDs, safe to commit |

What is **not** replicated and why:

- **Air-gapping** — the enterprise reference is permanently
  air-gapped; the lab has internet access and uses it for image and
  chart downloads. The synchronization flows of an air-gapped
  environment (Hauler Registry, git bundles) aren't useful to
  reproduce here.
- **Multi-node / true HA** — k3d supports simulated multi-node but
  always on the same physical host. No real failover, scheduling
  across zones, or network partition testing.
- **Database-as-a-Service** — in the target, databases are managed
  services (Nutanix NDB). Locally they run as pods inside the
  cluster. The deployment model differs but the application-level
  interfaces are the same.

## Roadmap

Done:

- [x] Phase 1 — k3d cluster with versioned configuration
- [x] Phase 2 — Argo CD bootstrap with app-of-apps pattern
- [x] Phase 3 — Sealed Secrets controller
- [x] Phase 3 — MongoDB 7.0 with replica set and SCRAM auth
- [x] Phase 3 — Keycloak with preconfigured realm
- [x] Phase 3 — Apache Apisix as gateway with TLS edge termination
- [x] Phase 4 Step 1A — `lcnpages-app` repository scaffolding (Spring Boot 4 + Angular 21)
- [x] Phase 4 Step 1B — Keycloak client `lcnpages-frontend` configured, test user, OIDC flow verified
- [x] Reorganization — split inline Phase 1/2 walkthroughs into `docs/setup/`

In progress / planned:

- [ ] Phase 4 Step 1C — Backend (Spring Boot resource server) and frontend (Angular SPA) implementation
- [ ] Phase 4 Step 1D — Kubernetes deploy via Argo CD with TLS via Apisix
- [ ] Phase 4 Step 2+ — Block editor, attachments, advanced search, AI features (post-MVP)
- [ ] Phase 5 — OpenSearch and observability stack (optional, on-demand)
- [ ] Phase 5 — Argo CD OIDC federation with Keycloak
- [ ] Phase 6 — MinIO as Nutanix Objects equivalent
- [ ] Architecture overview document (`docs/architecture.md`)

## Contributing

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md)
for operational guidelines and
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) for the adopted code of
conduct (Contributor Covenant 2.1).

Before opening a pull request, open an issue to discuss the proposed
change. If the change touches an architectural decision, add or
update an ADR in [`docs/adr/`](docs/adr/).

## License

Distributed under the [Apache License 2.0](LICENSE).

Copyright 2026 Angelo Fiorillo.
