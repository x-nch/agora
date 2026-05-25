# Architecture

## High-Level Design

The Agora platform Phase 2 runs on Amazon EKS with a namespace-based multi-tenant architecture. Four core microservices provide city management capabilities, isolated from tenant (inventors) workloads.

## Namespace Layout

```
cluster/
├── city-services/          # Core microservices (managed team)
│   ├── traffic-optimizer   # HTTP :8080
│   ├── energy-management   # HTTP :8080
│   ├── data-broker         # HTTP :8080, Kafka consumer
│   └── api-gateway         # HTTP :8080, HTTPS :8443
├── inventors/              # Tenant workloads (self-service)
│   └── <tenant apps>
└── monitoring/             # Observability stack
    ├── prometheus          # :9090
    └── grafana             # :3000
```

## Data Flow

```
Internet
    │
    ▼
ALB (AWS Load Balancer)
    │
    ▼
api-gateway (city-services)
    │
    ├──▶ traffic-optimizer ──▶ Kafka (MSK) ◀── data-broker
    │                              │
    └──▶ energy-management        │
                                  │
                             data-broker ──▶ Inventors (via API)
```

1. **Ingress**: External traffic enters through an AWS ALB (Ingress resource with `alb` ingress class). The ALB terminates TLS and forwards to the api-gateway service.

2. **API Gateway**: Routes requests to the appropriate backend based on path:
   - `/api/v1/traffic` → traffic-optimizer
   - `/api/v1/energy` → energy-management
   - `/api/v1/data` → data-broker
   - `/` → default api-gateway routing

3. **Data Broker**: Consumes from Amazon MSK (Kafka), processes streaming data, and exposes it via REST. Uses IRSA (IAM Roles for Service Accounts) for MSK authentication.

4. **Traffic Optimizer**: Processes real-time traffic data from Kafka, applies optimization algorithms.

5. **Energy Management**: Manages smart grid distribution, reads processed data from data-broker.

6. **Inventors**: Tenant namespace that accesses city-services through the api-gateway only. No direct Kafka access.

## Service Mesh Layer (Istio)

The Agora platform runs an Istio service mesh providing mTLS, authorization, observability, and traffic management. All mesh resources are defined under `kustomization/base/istio/` and deploy via Kustomize.

### Istio Resources

| Resource | Namespace | Purpose | Key Configuration |
|----------|-----------|---------|-------------------|
| `PeerAuthentication` (default) | `city-services` | Enforce **STRICT** mTLS — all intra-mesh traffic requires mutual TLS | `mode: STRICT` |
| `PeerAuthentication` (default) | `inventors` | Enforce **STRICT** mTLS for tenant workloads | `mode: STRICT` |
| `PeerAuthentication` (mesh-default) | `istio-system` | **PERMISSIVE** mode for mesh-internal components | `mode: PERMISSIVE` |
| `AuthorizationPolicy` (deny-all) | `city-services` | **Deny-by-default** — no traffic allowed unless explicitly permitted | Empty spec (matches all) |
| `AuthorizationPolicy` (traffic-optimizer) | `city-services` | Allow `GET`/`POST` from city-services and Prometheus | Principals: SA/default, SA/prometheus-sa |
| `AuthorizationPolicy` (data-broker) | `city-services` | Allow access from energy-management and traffic-optimizer SAs | Principals by SA name |
| `AuthorizationPolicy` (public-api) | `city-services` | Allow `inventors` namespace → public API paths | Paths: `/v1/public/*` |
| `Sidecar` (inventor-restricted) | `inventors` | Restrict egress to only api-gateway + istio-system | `REGISTRY_ONLY` mode |
| `Sidecar` (city-service-internal) | `city-services` | Restrict egress to city-services + monitoring + istio-system | `REGISTRY_ONLY` mode |
| `RequestAuthentication` (require-jwt) | `city-services` | Validate JWT from internal IdP | Issuer: `idp.agora.woven-city.internal` |
| `RequestAuthentication` (require-jwt) | `inventors` | Validate JWT from external IdP | Issuer: `auth.agora.woven-city.global` |
| `Telemetry` (mesh-default) | `istio-system` | 100% sampling rate, Zipkin tracing, Envoy access logs | `randomSamplingPercentage: 100.0` |
| `Telemetry` (detailed-logging) | `city-services` | Log all requests (ANY mode) — full visibility for city-services | `mode: ANY` |
| `Telemetry` (inventor-error-logging) | `inventors` | Log client+server errors only (≥400 or code=0) | `mode: CLIENT_AND_SERVER` |
| `ConfigMap` (istio-mesh-config) | `istio-system` | Global defaults — registry-only traffic, JSON logging, drain duration | `concurrency: 2`, `terminationDrainDuration: 5s` |

### Security Layering

Istio adds a **second security layer** on top of Kubernetes NetworkPolicies:

```
Pod A ──► NetworkPolicy (L3/L4: IP/port allow) ──► Istio (L7: mTLS + authz + JWT) ──► Pod B
```

| Layer | Technology | Scope | Enforcement |
|-------|-----------|-------|-------------|
| Network isolation | Kubernetes NetworkPolicy | L3/L4 (IP, port) | Cluster-wide, before pod receives traffic |
| Service mesh | Istio AuthorizationPolicy | L7 (HTTP method, path, JWT claims) | At sidecar proxy, after mTLS termination |
| Encryption in transit | Istio PeerAuthentication (STRICT) | All service-to-service traffic | Mutual TLS between sidecars |

### Data Flow with Istio

```
                           ┌──────────────┐
                           │  Istio Ingress │
                           │  Gateway       │
                           └──────┬───────┘
                                  │ Mutual TLS (mTLS)
                                  ▼
                     ┌────────────────────┐
                     │  Istio Sidecar     │
                     │  (istio-proxy)     │
                     │  + app container   │
                     └────────────────────┘
                              │
                    JWT Auth ↓  ↑ mTLS
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
      traffic-optimizer  data-broker   energy-mgmt
      (deny-all +        (deny-all +    (deny-all +
       per-service allow) per-service    per-service
                          allow)         allow)
```

### Service Mesh Considerations

- All inter-service communication uses HTTP REST on port 8080
- Network policies enforce least-privilege access between services (L3/L4)
- Istio enforces additional L7 authorization on top of network policies
- Prometheus scrapes metrics from `/actuator/prometheus` endpoint on each service
- PodDisruptionBudgets ensure minimum availability during node maintenance

## High Availability

- Multiple replicas spread across availability zones via pod anti-affinity
- Horizontal Pod Autoscalers adjust replica counts based on CPU/memory
- Rolling update strategy with `maxUnavailable: 0` ensures zero-downtime deployments
