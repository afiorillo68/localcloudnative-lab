# Setup walkthroughs

Step-by-step walkthroughs for setting up the lab from scratch.
Read these in order on first installation; you won't need them
again afterwards.

| Document | What it covers |
|---|---|
| [Phase 1 — Local Kubernetes cluster](phase-1-cluster.md) | Creating the k3d cluster, configuration, sanity test |
| [Phase 2 — GitOps with Argo CD](phase-2-argocd.md) | Bootstrapping Argo CD, app-of-apps pattern, UI access |

After Phase 2, the platform components in `platform/` (Sealed
Secrets, MongoDB, and future ones) are deployed automatically by
Argo CD. Some of them (notably MongoDB) require credentials to be
generated locally with `kubeseal`; see the
[Sealed Secrets operations runbook](../how-to/sealed-secrets-operations.md)
in section 5.

For day-to-day operations after setup is complete, see the main
[README](../../README.md) section "Daily operations".

For problems encountered during or after setup, see
[Troubleshooting](../troubleshooting.md).
