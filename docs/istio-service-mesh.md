# Istio Service Mesh — Agora Platform

> **Zero-trust service mesh layer for all pod-to-pod communication.**
> **Enforcement**: PeerAuthentication (STRICT mTLS), AuthorizationPolicy (deny-by-default + per-service allow), Sidecar egress restrictions, RequestAuthentication (JWT), MeshConfig (REGISTRY_ONLY).
> **Last Updated**: May 2026

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Two-Namespace Model](#2-two-namespace-model)
3. [PeerAuthentication — STRICT mTLS](#3-peerauthentication--strict-mtls)
4. [AuthorizationPolicy — Deny-by-Default](#4-authorizationpolicy--deny-by-default)
5. [Sidecar — Egress Restrictions](#5-sidecar--egress-restrictions)
6. [RequestAuthentication — JWT Validation](#6-requestauthentication--jwt-validation)
7. [MeshConfig — Registry-Only Outbound](#7-meshconfig--registry-only-outbound)
8. [Telemetry and Tracing](#8-telemetry-and-tracing)
9. [Defense-in-Depth Layering](#9-defense-in-depth-layering)
10. [Operational Notes](#10-operational-notes)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   istio-system (Control Plane)                │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  istiod — Discovery, CA, Config                         │ │
│  │  • SPIFFE X.509 certs (24h rotation)                    │ │
│  │  • Envoy proxy config distribution                      │ │
│  │  • Telemetry collection (Zipkin tracing)                │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
         │            │            │            │
         ▼            ▼            ▼            ▼
┌─────────────────────────────────────────────────────────────┐
│                    city-services Namespace                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐ │
│  │ Traffic  │  │  Energy  │  │   Data   │  │  API Gateway │ │
│  │ Optimizer│  │Management│  │  Broker  │  │              │ │
│  │  +Envoy  │  │  +Envoy  │  │  +Envoy  │  │   +Envoy   │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬───────┘ │
│       │              │             │               │          │
│       └──────────────┴─────────────┴───────────────┘          │
│                     ▲ All traffic: STRICT mTLS                │
└──────────────────────────────────────────────────────────────┘
         │
         │ (egress only to api-gateway)
         ▼
┌─────────────────────────────────────────────────────────────┐
│                     inventors Namespace                       │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Inventor App + Envoy                                    │ │
│  │  • REGISTRY_ONLY outbound                                │ │
│  │  • Can only reach: api-gateway, istio-system             │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

All Istio YAML resources are in `agora-kubernetes-components/kustomization/base/istio/`.

---

## 2. Two-Namespace Model

Istio resources mirror the same two workload namespaces as the platform:

| Namespace | PeerAuthentication | AuthorizationPolicy | Sidecar |
|-----------|-------------------|-------------------|---------|
| `city-services` | STRICT mTLS | deny-all + per-service allow rules | REGISTRY_ONLY, egress to city-services/ monitoring/ istio-system |
| `inventors` | STRICT mTLS | No namespace-wide policy (default deny) | REGISTRY_ONLY, egress only to api-gateway and istio-system |
| `istio-system` | PERMISSIVE | N/A | N/A |

The mesh-wide default in `istio-system` is PERMISSIVE to allow ingress gateways and the control plane to accept non-mTLS traffic (e.g., health checks from the AWS ALB).

---

## 3. PeerAuthentication — STRICT mTLS

Both workload namespaces enforce **STRICT** mTLS mode:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: city-services
spec:
  mtls:
    mode: STRICT
```

Every pod-to-pod connection uses mutual TLS with SPIFFE identities:
- **Pod identity**: `spiffe://cluster.local/ns/<namespace>/sa/<serviceaccount>`
- **Cert rotation**: Every 24 hours by istiod
- **STRICT mode**: Rejects plaintext at the Envoy proxy level — before the application sees the request

A pod without an Envoy sidecar (e.g., a misconfigured third-party app in `inventors`) cannot reach city-services, regardless of NetworkPolicy.

### Source

[`istio/peer-authentication.yaml`](https://github.com/woven-by-toyota/agora/blob/main/agora-kubernetes-components/kustomization/base/istio/peer-authentication.yaml)

---

## 4. AuthorizationPolicy — Deny-by-Default

A global `deny-all` policy blocks all traffic in `city-services`:

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: city-services
spec: {}
```

Per-service allow policies then selectively open traffic:

| Service | Allowed Sources | Allowed Operations |
|---------|----------------|-------------------|
| `traffic-optimizer` | city-services/default SA, monitoring/prometheus-sa | GET/POST `/api/*`, `/metrics` |
| `data-broker` | energy-management SA, traffic-optimizer SA, monitoring/prometheus-sa | GET/POST `/api/*`, `/metrics` |
| `api-gateway` | inventors namespace, city-services namespace | GET/POST `/v1/public/*` |

### Source

[`istio/authorization-policy.yaml`](https://github.com/woven-by-toyota/agora/blob/main/agora-kubernetes-components/kustomization/base/istio/authorization-policy.yaml)

---

## 5. Sidecar — Egress Restrictions

Two Sidecar resources limit what pods in each namespace can discover and reach:

### inventor-restricted (inventors namespace)

Inventor pods can only egress to the API gateway and Istio control plane:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Sidecar
metadata:
  name: inventor-restricted
  namespace: inventors
spec:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
    - hosts:
        - "city-services/api-gateway.city-services.svc.cluster.local"
        - "istio-system/*"
```

### city-service-internal (city-services namespace)

City service pods can egress within the namespace plus monitoring and Istio:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Sidecar
metadata:
  name: city-service-internal
  namespace: city-services
spec:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
    - hosts:
        - "city-services/*"
        - "monitoring/*"
        - "istio-system/*"
```

### Source

[`istio/sidecar.yaml`](https://github.com/woven-by-toyota/agora/blob/main/agora-kubernetes-components/kustomization/base/istio/sidecar.yaml)

---

## 6. RequestAuthentication — JWT Validation

Each namespace validates JWTs at the Envoy proxy before forwarding requests:

| Namespace | Issuer | Purpose |
|-----------|--------|---------|
| `city-services` | `https://idp.agora.woven-city.internal` | Internal service identities |
| `inventors` | `https://auth.agora.woven-city.global` | External inventor identities |

```yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: require-jwt
  namespace: city-services
spec:
  jwtRules:
    - issuer: "https://idp.agora.woven-city.internal"
      jwksUri: "https://idp.agora.woven-city.internal/.well-known/jwks.json"
```

### Source

[`istio/request-authentication.yaml`](https://github.com/woven-by-toyota/agora/blob/main/agora-kubernetes-components/kustomization/base/istio/request-authentication.yaml)

---

## 7. MeshConfig — Registry-Only Outbound

The mesh-level ConfigMap enforces REGISTRY_ONLY outbound traffic — pods cannot make direct connections to arbitrary IPs:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: istio-mesh-config
  namespace: istio-system
data:
  mesh: |-
    outboundTrafficPolicy:
      mode: REGISTRY_ONLY
    enableTracing: true
    accessLogFile: /dev/stdout
    accessLogEncoding: JSON
    defaultConfig:
      proxyMetadata:
        LOG_LEVEL: warning
      concurrency: 2
      terminationDrainDuration: 5s
    trustDomain: cluster.local
```

Three layers of egress control (defense-in-depth):

| Layer | Scope | Mechanism |
|-------|-------|-----------|
| MeshConfig | Cluster-wide | REGISTRY_ONLY — no arbitrary outbound connections |
| Sidecar | Per-namespace | Egress allow-list to specific services |
| NetworkPolicy | Kubernetes-level | Default-deny, allow-list per namespace |

### Source

[`istio/mesh-config.yaml`](https://github.com/woven-by-toyota/agora/blob/main/agora-kubernetes-components/kustomization/base/istio/mesh-config.yaml)

---

## 8. Telemetry and Tracing

| Feature | Configuration |
|---------|---------------|
| Tracing | Zipkin provider, **100% random sampling** |
| Access logging | JSON format to stdout |
| city-services logging | All requests (mode: ANY) |
| inventors logging | Only errors (response code >= 400) |

The mesh-level Telemetry resource enables Zipkin-compatible tracing with 100% sampling. A separate Telemetry resource in `city-services` enables detailed access logging for all requests. The `inventors` namespace logs only errors to reduce log volume.

### Source

[`istio/telemetry.yaml`](https://github.com/woven-by-toyota/agora/blob/main/agora-kubernetes-components/kustomization/base/istio/telemetry.yaml)

### Grafana Dashboards

An Istio services dashboard is available at:
- [`agora-observability/kustomization/base/grafana/dashboards/istio-services.json`](https://github.com/woven-by-toyota/agora/blob/main/agora-observability/kustomization/base/grafana/dashboards/istio-services.json)

---

## 9. Defense-in-Depth Layering

Istio adds a **third layer** of security on top of existing controls:

| Layer | Scope | Mechanism |
|-------|-------|-----------|
| VPC Security Groups | Network boundary | AWS-managed, per-AZ |
| Kubernetes NetworkPolicy | Namespace isolation | Default-deny, allow-list |
| **Istio mTLS + Authz** | **Pod-to-pod identity** | **SPIFFE, JWT, STRICT mTLS** |
| IAM (IRSA) | AWS API access | ServiceAccount-bound roles |
| RBAC | K8s API access | Role/ClusterRole bindings |

The Istio layer is **identity-aware** (SPIFFE), not just network-aware. Even if a NetworkPolicy is misconfigured to allow traffic, Istio will still reject it if the source identity is not authorized.

---

## 10. Operational Notes

### Sidecar Injection

All core deployments use the annotation for automatic sidecar injection:

```yaml
metadata:
  labels:
    sidecar.istio.io/inject: "true"
```

Both `city-services` and `inventors` namespaces have the Istio injection label:
```yaml
metadata:
  labels:
    istio-injection: enabled
```

### Health Check Noise Suppression

To suppress health check log noise from istio-proxy, add the following to any MeshConfig or EnvoyFilter:

```yaml
match: drop istio-proxy /healthz
```

### Known Limitation

The `istio-system` namespace uses PERMISSIVE mode to accept health checks from the AWS ALB (which doesn't have a sidecar). Future enhancement: migrate to STRICT + ServiceEntry for ALB health probes.

### Related Documentation

- [Architecture Overview](ARCHITECTURE.md#12-istio-service-mesh) — Full architecture doc with Istio section
- [Security Architecture](SECURITY.md) — Platform-wide security context
- [`agora-kubernetes-components/kustomization/base/istio/`](https://github.com/woven-by-toyota/agora/tree/main/agora-kubernetes-components/kustomization/base/istio/) — All Istio resource YAML files
