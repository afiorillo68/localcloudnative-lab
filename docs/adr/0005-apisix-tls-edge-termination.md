# ADR-005 — TLS edge termination pattern with Apache Apisix

**Status**: Accepted (2026-05-09)
**Related**: ADR-001 (GitOps strategy), ADR-004 (standalone etcd)

---

## Context

Following Phase 3 Step 5, Apache Apisix terminates TLS at the edge
gateway for all services exposed via `ApisixRoute`. Backend services
(Argo CD, Keycloak, and future workloads) listen on plain HTTP on
their internal `ClusterIP` Service; Apisix decrypts the inbound HTTPS
request, forwards it as plain HTTP to the backend, and re-encrypts
the response.

This is the standard "edge TLS termination" pattern and is the
default for cloud-native gateways (Apisix, Nginx Ingress, Traefik,
HAProxy). It centralizes certificate management at the gateway and
keeps backend pod configuration simpler.

However, edge termination introduces three classes of subtle
configuration requirements that, if not handled, cause the backend
to misbehave:

1. **Backend "knowing" it is behind a proxy** — the backend must
   trust forwarded headers (`X-Forwarded-Proto`, `X-Forwarded-Port`,
   `X-Forwarded-Host`) to construct correct redirects, OAuth
   callbacks, asset URLs, and CSRF protections. Without this, the
   backend assumes its scheme/port/host based on local configuration
   and produces broken redirects to plain HTTP, wrong port numbers,
   or OAuth flows that fail at the redirect step.

2. **Gateway propagating forwarded headers** — Apisix does not inject
   `X-Forwarded-Proto: https` automatically on every route. The
   `proxy-rewrite` plugin must be configured explicitly per route
   to set the header, otherwise the backend receives only the
   downstream request as-is.

3. **Backend hostname configuration overriding port detection** —
   some backends (notably Keycloak 25+) construct external URLs
   from a configured `hostname` parameter that, when set as a bare
   hostname, defaults the port to the inbound HTTP listener port
   (9443 in the Apisix container) rather than the publicly mapped
   port (443). Setting the hostname as a full URL with scheme
   (`https://host`) is required to suppress port appending.

These requirements are not unique to Apisix; they apply to any edge
TLS termination pattern. They emerged in this lab during the rollout
of Argo CD and Keycloak as backends behind Apisix in Phase 3 Step 5.

---

## Decision

Adopt a documented three-part pattern for every backend service
exposed via `ApisixRoute`:

### Part 1 — Apisix `ApisixRoute` includes `proxy-rewrite` plugin

Every `ApisixRoute` must include the `proxy-rewrite` plugin to
inject forwarded headers, even when the headers seem redundant:

```yaml
spec:
  ingressClassName: apisix
  http:
    - name: <route-name>
      match:
        hosts: [<hostname>]
        paths: ["/*"]
      backends:
        - serviceName: <service>
          servicePort: <port>
      plugins:
        - name: proxy-rewrite
          enable: true
          config:
            headers:
              set:
                X-Forwarded-Proto: https
                X-Forwarded-Port: "443"
```

### Part 2 — Backend trusts forwarded headers

Each backend has a different mechanism. Documented for current
backends:

**Argo CD (v2.13.x)**:
- Set `server.insecure: "true"` in `argocd-cmd-params-cm`
  (the `argocd-cm` ConfigMap is the wrong location — `server.insecure`
  is read as a startup parameter, not a server config setting)
- This disables Argo CD's own redirect-to-HTTPS behavior, allowing
  Apisix to handle TLS termination

**Keycloak (26.x via Bitnami chart)**:
- Set `extraEnvVars: KC_PROXY_HEADERS=xforwarded` (the `proxy: edge`
  values parameter is **deprecated and inactive** in Bitnami chart 24+;
  the modern Keycloak environment variable is `KC_PROXY_HEADERS`)
- Set `extraEnvVars: KC_HOSTNAME=https://<hostname>` (full URL with
  scheme, not just hostname; required since Keycloak 25 to suppress
  port appending in generated URLs)

### Part 3 — Hostname resolution

The user's `/etc/hosts` (or DNS in production) must resolve the
hostname to the gateway's ingress IP, not to backend pods:

```
127.0.0.1 argocd.lcn-lab.local keycloak.lcn-lab.local
```

In the lab, the gateway is the Apisix `LoadBalancer` Service exposed
via klipper-lb on `127.0.0.1:443`.

---

## Consequences

**Positive**:

- Centralized TLS termination simplifies certificate management
- Backends remain simpler (no TLS configuration on each pod)
- Pattern is consistent and replicable for future workloads

**Negative**:

- Each backend has its own quirks for trusting forwarded headers;
  there is no universal recipe. Documentation per backend is essential
- Misconfiguration produces silent or partial failures (redirect
  loops, wrong ports, broken OAuth) that are hard to diagnose without
  knowing the pattern in advance
- Future backends may have additional, different requirements not
  captured here

**Documentation requirement**: when adding a new workload behind
Apisix, the developer must verify and document:

1. The backend-specific mechanism for trusting forwarded headers
2. Any hostname/port configuration peculiarities
3. The resulting plugin configuration on the `ApisixRoute`

These notes should be added to `docs/troubleshooting.md` or, if the
backend introduces a substantially new pattern, an extension to this
ADR.

---

## History

- **2026-05-09**: Pattern emerged during Phase 3 Step 5 closure
  (commits `a3032b9`, `c5f8680`, `2aec965`, `851f547`); formalized
  as ADR after the fact to consolidate the three-part requirement
  for future workloads
