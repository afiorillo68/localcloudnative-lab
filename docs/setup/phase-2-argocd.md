# Phase 2 — GitOps with Argo CD

This document walks through bootstrapping Argo CD with the manifest
versioned in this repo, having Argo CD self-manage via the
**app-of-apps pattern**, and from there deploying all platform
services as Argo CD Applications pointing to the `platform/`
directories of this repo.

## Goal

Bootstrap Argo CD so that:

1. Argo CD is installed in the cluster from manifests committed in
   this repo (no runtime downloads).
2. Argo CD manages itself: changes to the Argo CD configuration in
   the repo are applied automatically by Argo CD on the next sync.
3. From there, all platform components (Sealed Secrets, MongoDB,
   and future ones) are deployed as Argo CD Applications.

## Configuration files

Everything needed to install and configure Argo CD lives in
`platform/argocd/`. Anyone who clones the repo gets exactly the same
installation, with no dependencies on external resources at deploy
time.

```
platform/argocd/
├── install.yaml          # Upstream Argo CD v2.13.3 manifest (vendored)
├── kustomization.yaml    # Overlay: base=install.yaml + dev CM patch
└── argocd-cm-patch.yaml  # ConfigMap patch: insecure mode, annotation tracking
```

**`install.yaml`** is the official Argo CD manifest, downloaded once
and committed to the repo. It is not downloaded at runtime: the
bootstrap uses local files only. To upgrade Argo CD, download the
new version of the manifest, update `kustomization.yaml`, and push
— Argo CD will upgrade itself on the next sync cycle.

**`kustomization.yaml`** combines base and patch in a single atomic
apply: install and configuration are applied together, not in
separate steps.

**`argocd-cm-patch.yaml`** sets three parameters for the lab:

| Parameter | Value | Reason |
|---|---|---|
| `server.insecure` | `"true"` | Disables TLS on Argo CD's own server; TLS termination delegated to Apisix (Phase 3) |
| `application.resourceTrackingMethod` | `annotation` | More reliable with Helm charts that already carry their own labels |
| `timeout.reconciliation` | `300s` | Margin for slow pulls in the lab |

## App-of-apps pattern

```
gitops/applications/root-app.yaml   ← applied once via kubectl (bootstrap)
        │
        ▼  Argo CD syncs the gitops/applications/ directory
   ┌────────────────────────────────────────────────────────┐
   │  gitops/applications/                                  │
   │  ├── argocd-app.yaml          → platform/argocd/       │ Argo CD self-manages
   │  ├── sealed-secrets-app.yaml  → platform/sealed-secrets/
   │  ├── mongodb-app.yaml         → platform/mongodb/
   │  ├── keycloak-app.yaml        → platform/keycloak/  [F3]
   │  └── apisix-app.yaml          → platform/apisix/    [F3]
   └────────────────────────────────────────────────────────┘
```

The root Application is the only resource applied manually (one-time
bootstrap). Everything else — including Argo CD itself — is managed
via GitOps: every `git push` to the `main` branch is reflected in the
cluster on the next sync cycle.

The `[F3]` Applications exist in the repo but lack
`syncPolicy.automated`: they don't deploy anything until the
respective `platform/` directories are populated with Helm charts or
Kubernetes manifests.

## Prerequisites

- `lcn-lab` cluster active (Phase 1 complete)
- `kubectl` in the PATH and context pointed at `k3d-lcn-lab`
- Repo pushed to GitHub (required for the GitOps flow)
- GitHub Personal Access Token with `repo` scope (for private repos)

## Bootstrap (one-time, after cloning the repo)

```bash
# From the repo root
GH_TOKEN=<github-personal-access-token> \
  ./bootstrap/argocd-bootstrap.sh
```

The script runs in sequence:

1. **Preflight**: verifies `kubectl` points to `k3d-lcn-lab` and
   that `platform/argocd/install.yaml` exists in the cloned repo.
2. **Namespace**: `kubectl create namespace argocd` (idempotent).
3. **Installation**: `kubectl apply -k platform/argocd/` — single
   command that applies `install.yaml` + `argocd-cm-patch.yaml`
   atomically.
4. **Wait**: rollout status on `argocd-server`,
   `application-controller`, `repo-server`.
5. **Repo credentials**: creates the Argo CD Secret with the GitHub
   token to access the private repo.
6. **Root Application**: applies `gitops/applications/root-app.yaml`
   — from this point on, Argo CD manages itself and the child
   Applications.
7. **Summary**: prints admin password, pod status, Application
   status.

Expected time: ~2-3 minutes (container image pull on first run).

## UI access

```bash
make argocd-ui
# Open: https://localhost:8090
```

The command runs preliminary checks (cluster reachable, port 8090
free) and then launches `kubectl port-forward -n argocd
svc/argocd-server 8090:443`. Press `Ctrl-C` to close the tunnel.

The browser will warn about Argo CD's self-signed certificate: click
*Advanced → Proceed anyway* (or equivalent). The warning is normal
and does not indicate a security problem in the local lab context.

```bash
# Retrieve the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode; echo
```

> **Note — port-forward and process lifecycle**: the `kubectl
> port-forward` tunnel is a process that lives in the shell where
> it was launched. If the shell is closed, the Mac sleeps, or the
> process is interrupted, the tunnel dies silently. The cluster is
> not broken: just relaunch `make argocd-ui`. See also
> [Troubleshooting](../troubleshooting.md).

> **Note — evolution in Phase 3**: in Phase 3, Apisix will be
> configured as the ingress controller. The Argo CD UI will be
> exposed via an ApisixRoute on a dedicated hostname (e.g.,
> `argocd.lcn-lab.local`), with TLS termination handled by Apisix
> and no need for port-forwards. This aligns the lab with the
> enterprise target pattern (centralized gateway for all admin
> consoles).

## Verification

```bash
# 1. All pods Running
kubectl get pods -n argocd

# 2. Argo CD CRDs present (3: applications, applicationsets, appprojects)
kubectl get crd | grep argoproj

# 3. Applications synced
kubectl get applications -n argocd
# expected: root, argocd, sealed-secrets, mongodb, keycloak, apisix
# all Synced/Healthy (keycloak and apisix may show "OutOfSync" until
# their platform/ directories are populated in Phase 3)

# 4. Argo CD self-management: edit argocd-cm-patch.yaml,
#    git push and observe automatic sync on the ConfigMap
kubectl get configmap argocd-cm -n argocd -o yaml | grep resourceTrackingMethod
# expected: application.resourceTrackingMethod: annotation
```

> **Note — `last-applied-configuration` warning on existing
> installations**: if you run `kubectl apply -k platform/argocd/` on
> a cluster where Argo CD was previously installed with `kubectl
> apply -f <url>` (without kustomize), kubectl emits warnings about
> missing annotations. This is not an error: the annotations are
> added automatically on the first apply and the warnings don't
> reappear. On a fresh installation (new cluster) they don't appear
> at all.

## Upgrading Argo CD

```bash
# 1. Download the new manifest
curl -fsSL https://raw.githubusercontent.com/argoproj/argo-cd/vX.Y.Z/manifests/install.yaml \
  -o platform/argocd/install.yaml

# 2. Update the version in platform/argocd/kustomization.yaml
#    and in bootstrap/argocd-bootstrap.sh (ARGOCD_VERSION variable)

# 3. Commit and push — Argo CD upgrades itself
git add platform/argocd/install.yaml platform/argocd/kustomization.yaml \
        bootstrap/argocd-bootstrap.sh
git commit -m "argocd: upgrade to vX.Y.Z"
git push
```

## Installed components

| Component | Version | Notes |
|---|---|---|
| argocd-server | v2.13.3 | HTTPS with self-signed cert; access via `make argocd-ui`; TLS termination via Apisix in Phase 3 |
| argocd-application-controller | v2.13.3 | StatefulSet, 1 replica |
| argocd-repo-server | v2.13.3 | Git manifest cache |
| argocd-dex-server | v2.13.3 | OIDC broker; integrates with Keycloak in Phase 3 |
| argocd-redis | v2.13.3 | Internal cache |
| argocd-applicationset-controller | v2.13.3 | For ApplicationSet (future use) |
| argocd-notifications-controller | v2.13.3 | Not configured in the lab |

## Next: Phase 3

After Argo CD is running and the Applications are Synced, the
platform components in Phase 3 are deployed:

- **Sealed Secrets** is bootstrapped automatically by Argo CD as
  soon as the root Application syncs. The CLI `kubeseal` is needed
  locally to generate SealedSecrets — see
  [Sealed Secrets operations runbook](../how-to/sealed-secrets-operations.md).

- **MongoDB** also deploys automatically once the SealedSecrets for
  the root and application credentials are generated and committed.
  Generation procedure: same runbook above, section 5.

- **Keycloak** and **Apache Apisix** are planned and not yet
  deployed.
