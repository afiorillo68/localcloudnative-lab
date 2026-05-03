# Troubleshooting

Common problems encountered when running this lab, with diagnoses
and fixes. Organized by symptom.

---

## Cluster and infrastructure

### `k3d cluster create` fails with network errors

Verify that OrbStack/Docker is running:

```bash
docker ps
# or, if context is not configured:
~/.orbstack/bin/docker ps
```

If the command fails, start OrbStack from the application.

### `k3d` cannot find the Docker daemon (`Cannot connect to Docker daemon`)

OrbStack exposes the socket at `~/.orbstack/run/docker.sock`. In some
shell configurations (e.g., tmux, remote login) the Docker context
may not be set. Solution:

```bash
export DOCKER_HOST=unix://${HOME}/.orbstack/run/docker.sock
k3d cluster create --config cluster/k3d-cluster.yaml
```

Alternatively, make sure the OrbStack initialization line is present
in your `.zshrc` / `.bashrc` (OrbStack adds it on first launch).

### Ports 80/443 already in use

Likely conflict with a local web server. Workaround: change the
ports in `cluster/k3d-cluster.yaml` (e.g., 8080/8443) and access at
`http://localhost:8080`.

### Slow performance / fans spinning loudly

On 16 GB of RAM it is easy to saturate. Tips:

- Keep only one k3d cluster active (`k3d cluster list`).
- Stop OpenSearch and the monitoring stack when not needed.
- Check OrbStack's memory limit (Settings → Resources): setting it
  to ~10-12 GB on a 16 GB Mac leaves margin for the system.

### `kubectl` points to the wrong cluster

```bash
kubectl config get-contexts
kubectl config use-context k3d-lcn-lab
```

---

## Argo CD

### The Argo CD UI stops responding after being accessible

**Symptom**: `make argocd-ui` had worked, the UI was open in the
browser, then it stopped responding (connection refused or timeout).

**Cause**: `kubectl port-forward` is a process — not a system
service. It only lives as long as the shell that launched it. If
that shell is closed, the Mac goes to sleep, the SSH session
expires, or the kubectl process is interrupted for any other reason,
the tunnel dies silently. The cluster is intact, the Argo CD pods
keep running: only the local access channel is missing.

**Solution**: relaunch the tunnel.

```bash
make argocd-ui
```

This is normal Kubernetes port-forward behavior and does not
indicate any breakage of the cluster or of Argo CD.

### An Argo CD Application is stuck in `Progressing` or `OutOfSync`

**Symptom**: an Application stays in `Progressing` for several
minutes, or shows `OutOfSync` even though everything looks fine.

**Diagnosis steps**:

1. Look at the per-resource sync status:
   ```bash
   kubectl -n argocd get application <app-name> \
     -o jsonpath='{range .status.resources[*]}{.kind}/{.name}: sync={.status} health={.health.status}{"\n"}{end}'
   ```
   This shows which specific resources are out of sync.

2. Open the UI (`make argocd-ui`), click on the Application, then
   open the **App Diff** tab. The diff between Git and the cluster
   is shown line-by-line.

**Two kinds of drift**:

- **Cosmetic drift**: fields auto-populated by the Kubernetes API
  server (e.g., `apiVersion: v1` and `kind: PersistentVolumeClaim`
  on `volumeClaimTemplates` of a StatefulSet). The Git manifest
  doesn't write them; the cluster does. Argo CD sees this as drift.
  **Fix**: add the fields explicitly to the Git manifest, or
  configure `ignoreDifferences` on the Application.

- **Substantive drift**: real differences caused by imperative
  interventions (manual `kubectl edit`, force patches), unratified
  Engineer choices, or external controllers. **Fix**: open the diff,
  understand what diverges, decide consciously whether to update
  Git to match the cluster or vice versa.

**Don't reflexively run `sync --force --prune` on substantive
drift**: it can destroy real configuration. Diagnose first.

### Argo CD CLI fails with `gRPC connection not ready`

**Cause**: the `argocd` CLI is connecting to localhost:8090, but the
port-forward is not active.

**Fix**:

1. In one terminal: `make argocd-ui` (leave it running).
2. In another terminal: `argocd login localhost:8090 --insecure
   --grpc-web --username admin`.

If you don't want to set up the CLI, the UI in the browser provides
the same functionality.

---

## Sealed Secrets

### `kubeseal: command not found`

The CLI is not installed locally. Install it:

```bash
brew install kubeseal
```

The CLI is needed only on the developer machine (your Mac) to
encrypt secrets before committing them to the repo. The decryption
side runs as a controller in the cluster and was deployed
automatically by Argo CD.

### A SealedSecret doesn't decrypt to a Secret

**Symptom**: the SealedSecret is present in the cluster but no
corresponding Secret is created. The pod that depends on the Secret
fails to mount it.

**Possible causes**:

1. The Sealed Secrets controller pod is not running. Check:
   ```bash
   kubectl -n platform-sealed-secrets get pods
   ```

2. The SealedSecret was encrypted with a different master key than
   the one currently in the cluster. This happens if the cluster was
   recreated and the master key wasn't restored from backup. Fix:
   regenerate all SealedSecrets with the new key (see
   [Sealed Secrets operations runbook](how-to/sealed-secrets-operations.md)).

3. Field name mismatch between the SealedSecret and what the
   consuming workload expects. Verify both manifests.

---

## MongoDB

### Pod `mongodb-0` in `Init:CrashLoopBackOff`

**Symptom**: the pod fails on the `init-keyfile` init container.

**Common causes**:

- The image used for the init container has a hardened rootfs that
  prevents Kubernetes from mounting the service account token. If
  you see errors like `read-only file system` near
  `/var/run/secrets/kubernetes.io/serviceaccount`, the init image is
  the problem. **Fix**: use `busybox:1.36` or another minimal image
  with a standard rootfs, not `mongo:8.0` or other "full" application
  images.

- The required SealedSecret is missing in the cluster. Check:
  ```bash
  kubectl -n platform-mongodb get secrets
  ```
  You should see `mongodb-root-credentials` and
  `mongodb-app-credentials`. If they're missing, follow section 5
  of the [Sealed Secrets operations runbook](how-to/sealed-secrets-operations.md).

### MongoDB pod logs say "kernel 6.19 incompatibility"

**Symptom**: the pod starts but immediately exits with a fatal log
mentioning `Linux kernel versions 6.19 and newer has a known
incompatibility with this version of MongoDB`.

**Cause**: MongoDB 8.x is incompatible with Linux kernel 6.19+ due
to a TCMalloc/Shadow Stack issue. OrbStack on Apple Silicon ships
kernel 6.19+. See https://www.mongodb.com/community/forums/t/mongodb-8-x-and-linux-kernel-6-19/337547

**Fix**: use MongoDB 7.0 instead of 8.x. The lab's manifest already
uses `mongo:7.0` (see ADR-003 amendment dated 2026-05-02). If you've
manually changed it to 8.x, revert.

### The `mongodb` Application stays `OutOfSync` after troubleshooting

**Symptom**: after several manual interventions during a debugging
session, the `mongodb` Application shows `OutOfSync` permanently
even though everything else is healthy.

**Diagnosis**: usually it's cosmetic drift (see "An Argo CD
Application is stuck" above). For MongoDB specifically, the most
common case is the StatefulSet's `volumeClaimTemplate` getting
auto-completed by the API server with `apiVersion: v1` and
`kind: PersistentVolumeClaim`.

**Fix**: add those two fields explicitly in the Git manifest, push,
and the Application returns to Synced.

### Init Job `mongodb-rs-initiate` reports `User already exists` but the user doesn't exist

**Symptom**: the Job logs say "User X already exists, skip", but
running `db.adminCommand('usersInfo', {forAllDBs: true})` shows the
user doesn't actually exist anywhere.

**Cause**: idempotency check bug in the Job. The check returns a
truthy value even when the user is absent, so the creation step is
skipped.

**Fix**: the current Job uses an explicit `=== null` check that
prints `NO`/`YES` and a shell-side comparison. If you've manually
modified the Job logic and reintroduced a truthy/falsy check,
revert. End-to-end verification (querying the user list directly)
should always be part of post-deploy checks.

---

## General principles

A few things we've learned the hard way during this lab's
development:

- **Exit code 0 is not the same as success**. A bash script with
  `set -e` exits 0 if the last command succeeded, even if a previous
  command silently did the wrong thing. Always include end-to-end
  verification in runbooks (does the database exist? can the user
  authenticate?), not just infrastructure checks (is the pod
  Running?).

- **An agent reporting "done" is necessary but not sufficient**.
  Verify the applicative outcome before considering a task closed.

- **Don't reflexively `--force --prune`**. Diagnose drift first.
  Force operations on cosmetic drift are harmless; force operations
  on substantive drift can destroy real configuration.

- **Patch carefully on existing installations**. Strategic merge
  patches on ConfigMaps without a `data:` section can fail silently.
  Verify the cluster state matches your intent.
