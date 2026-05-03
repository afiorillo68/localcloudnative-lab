# Phase 1 — Local Kubernetes cluster

This document walks through creating the local Kubernetes cluster
that hosts everything else: Argo CD, Sealed Secrets, MongoDB, and
the platform components that come in later phases.

## Goal

Create a single-node Kubernetes cluster with `k3d`, exposed on
standard HTTP/HTTPS ports, ready to host Argo CD and the platform
services in subsequent phases.

## Design decisions

- **Single-node** in Phase 1. Simulated multi-node adds no value for
  development and doubles RAM consumption. We'll only enable it if
  we need to test affinity/anti-affinity rules.

- **K3s server with Traefik DISABLED**. K3s installs Traefik as the
  default ingress controller; we disable it because we'll use
  **Apache Apisix** as the gateway, consistent with the enterprise
  target.

- **`servicelb` (klipper-lb) DISABLED as well**. k3d handles
  exposure of LoadBalancer services through its own loadbalancer
  container; the internal K3s `servicelb` is redundant.

- **Port mapping 80 and 443** on the k3d loadbalancer, so apps
  exposed via Apisix will be reachable at `http://localhost`
  without manual port-forwards.

- **Integrated local registry** (`k3d-registry.localhost:5000`) for
  pushing locally-built images without going through Docker Hub.
  Replaces Harbor for the development phase.

## Configuration file

The cluster is defined declaratively in
[`cluster/k3d-cluster.yaml`](../../cluster/k3d-cluster.yaml). All
parameters are versioned: to recreate the cluster from scratch,
re-run the `k3d cluster create --config` command.

## Cluster creation

```bash
# From the repo root
k3d cluster create --config cluster/k3d-cluster.yaml
```

Creation time: ~30-60 seconds on first run (image downloads), ~15
seconds on subsequent runs.

## Verification

```bash
# kubectl context is set automatically by k3d
kubectl config current-context
# expected: k3d-lcn-lab

# Nodes
kubectl get nodes
# expected: 1 node "Ready", role control-plane,master

# System pods
kubectl get pods -A
# expected: coredns, local-path-provisioner, metrics-server in Running state
# traefik must NOT appear (we disabled it)

# Local registry
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep registry
# expected: container registry.localhost running on port 5000
# Note: container name is "registry.localhost" (not "k3d-registry.localhost")
# as defined in cluster/k3d-cluster.yaml → registries.create.name
```

> **Operational note — registry container name**: the local registry
> container is named `registry.localhost` (not
> `k3d-registry.localhost`). The naming is determined by the
> `registries.create.name` field in `cluster/k3d-cluster.yaml`. The
> hostname to use in image tags remains `k3d-registry.localhost:5000`
> because k3d automatically adds a DNS alias inside the `k3d-lcn-lab`
> network.

## Sanity test

Deploy a test nginx to verify that pods, services, and port mapping
work:

```bash
kubectl create deployment sanity-nginx --image=nginx:alpine
kubectl expose deployment sanity-nginx --port=80 --type=ClusterIP
kubectl port-forward svc/sanity-nginx 8080:80
# In another terminal:
curl http://localhost:8080
# expected: HTML "Welcome to nginx!"

# Cleanup
kubectl delete deployment sanity-nginx
kubectl delete svc sanity-nginx
```

## Reset / destruction

```bash
# Stop the cluster (preserves state)
k3d cluster stop lcn-lab

# Start the existing cluster
k3d cluster start lcn-lab

# Complete destruction (also deletes volumes)
k3d cluster delete lcn-lab
```

For day-to-day operations (start, stop, status), see the Makefile
targets `lab-up`, `lab-down`, `lab-status` documented in the main
[README](../../README.md).

## Next: Phase 2

Once the cluster is up and verified, proceed to
[Phase 2 — GitOps with Argo CD](phase-2-argocd.md) to bootstrap
Argo CD and the app-of-apps pattern.
