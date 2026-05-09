# ADR-004 — Standalone etcd for Apache Apisix

**Status**: Accepted (2026-05-09)
**Promoted from**: `BACKLOG.md` proposed entry (2026-05-04)
**Related**: ADR-002 (Bitnami chart deprecation), ADR-003 (arm64 platform exception driver)

---

## Context

The upstream Apache Apisix Helm chart (`apisix/apisix` 2.14.0) bundles
`bitnami/etcd` as a subchart. The Bitnami etcd subchart registers Helm
hooks of type `pre-upgrade,pre-install` that create a JWT token Secret
needed for the etcd pod to start.

Argo CD interprets Helm hooks of type `pre-upgrade` and `pre-install`
as **PreSync hooks**, executing them before any other resource of the
Application is applied. The hook Job in the Bitnami etcd subchart
attempts to populate a Secret (`apisix-etcd-jwt-token`) that **the
etcd pod itself depends on** for boot — but the same Secret cannot
exist before the hook runs, because the hook is supposed to create it.

Result: a chicken-and-egg deadlock. The hook Job hangs waiting for the
Secret it should create; the Application never reaches the Sync phase;
the rest of the resources (gateway, Ingress Controller, ApisixRoute,
ApisixTls) are never deployed.

This issue surfaced during Step 5a of Phase 3 (Apisix bootstrap).
Initial workarounds considered:

| Option | Approach | Why rejected |
|---|---|---|
| A | Replace hook Job manually after first install | Imperative, breaks GitOps |
| B | Use Argo CD `syncOptions: SkipDryRunOnMissingResource` | Postpones the issue, doesn't solve it |
| C | Disable etcd subchart, deploy etcd standalone | Selected — see below |
| D | Switch to Apisix standalone mode (no etcd) | Loses dynamic CRD-driven config; out of scope |

---

## Decision

Disable the `bitnami/etcd` subchart in the Apisix chart values
(`etcd.enabled: false`) and deploy a standalone etcd as a separate
Kubernetes resource within the same `platform-apisix` namespace.

Configuration:

- **Image**: `quay.io/coreos/etcd:v3.5.21` (CoreOS upstream, multi-arch
  verified for amd64 and arm64 — required by ADR-003 platform driver)
- **Topology**: single-node StatefulSet, 1 replica
- **Authentication**: none (`ALLOW_NONE_AUTHENTICATION=yes`); the etcd
  Service is `ClusterIP`-scoped within the cluster network and not
  exposed externally
- **Persistence**: 2 GiB PVC backed by `local-path` storage class
- **Discovery**: Apisix gateway points at
  `etcd-standalone.platform-apisix.svc.cluster.local:2379` via
  `apisix.etcd.host` in chart values

The standalone etcd manifest is committed at
`platform/apisix/base/etcd-standalone.yaml` and managed by the same
Argo CD Application as the rest of Apisix.

---

## Consequences

**Positive**:

- Eliminates the Helm hook compatibility issue with Argo CD
- Removes Bitnami legacy dependency from the Apisix subsystem
  (consistent with ADR-002 direction of disengagement)
- Explicit ownership of the etcd component allows for finer
  configuration control (resource limits, persistence size, image
  version) without working around chart values

**Negative**:

- Adds a second declarative manifest (etcd) to the Apisix Application
  resources, increasing operational surface
- Single-node etcd is not production-grade; for production deployments
  a multi-node etcd cluster with TLS auth would be required
- StatefulSet `volumeClaimTemplate` triggers cosmetic drift in Argo CD
  (apiVersion/kind auto-populated by the API server) — same pattern
  observed for MongoDB; resolved with explicit fields in the manifest
  base or `ignoreDifferences` annotation on the Application

**Future work**:

- Phase 5+: evaluate replacing standalone etcd with a multi-node
  Apisix-managed etcd cluster, or migrating to Apisix standalone mode
  with declarative YAML configuration

---

## History

- **2026-05-04**: Proposed in `BACKLOG.md` after PreSync deadlock
  identified during Step 5a fallout
- **2026-05-04**: Implemented in commit `17fc438`
  (`fix(apisix): replace bitnami etcd subchart with standalone etcd`)
- **2026-05-09**: Promoted from BACKLOG to formal ADR after
  Phase 3 Step 5 final closure
