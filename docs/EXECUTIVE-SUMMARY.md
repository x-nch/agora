# Executive Summary — Agora Platform Infrastructure

> **Project**: Woven City Agora — City Operating System
> **Document**: Executive Summary for Stakeholders and Interviewers
> **Date**: May 2026
> **Role**: Platform Engineer / Infrastructure Architect

---

## The Opportunity

Woven City is the world's first fully-connected smart city at scale. Launched September 2025 at the base of Mount Fuji, it houses 360+ residents and runs 20+ external inventor programs backed by Toyota's ~$10B investment.

Agora is the city's operating system — orchestrating **60,000+ real-time events/second** from **10,000+ IoT devices** (autonomous vehicles, traffic signals, environmental sensors, building management systems) across **5 city districts** (Mobility, Living, Working, Wellness, Innovation).

**The infrastructure challenge**: Build a production-ready, multi-tenant, 99.95% available cloud platform that enables both internal city services (traffic optimization, energy management) and external inventor ecosystem (third-party APIs) — on AWS, in Japan.

---

## What Was Built

### Phase 1: Terraform Infrastructure-as-Code

A modular, production-ready Terraform framework (7 child modules, 3 environments) that any team can provision by editing a single `terraform.tfvars` file:

| Module | Purpose | Key Decision |
|--------|---------|-------------|
| **VPC** | Network foundation across 3 AZs | /16 CIDR, public/private/subnet isolation |
| **EKS** | Kubernetes cluster for 50+ microservices | Karpenter auto-scaling, OIDC + IRSA |
| **MSK** | Kafka event streaming for 60K msg/sec | Express brokers (prod) / Serverless (dev) |
| **RDS (Aurora)** | Transactional database + device registry | Aurora PostgreSQL — ~30s failover |
| **S3** | 4 data lake buckets with lifecycle policies | SSE-KMS, versioning, access logging |
| **Monitoring** | Infrastructure-level observability | CloudWatch + AMP (Prometheus is Phase 2) |
| **IAM** | Least-privilege access control | Service-specific IRSA roles for MSK IAM auth |

### Phase 2: Kubernetes Components & Multi-Tenancy

Complete K8s manifests for 4 core microservices with enterprise-grade isolation:

- **Namespace isolation**: `city-services` (internal) + `inventors` (external) + `monitoring`
- **RBAC**: Read-only inventors vs read-write city services
- **Network policies**: Default-deny, allow-listed traffic only
- **Resource quotas**: 5:1 ratio preventing noisy-neighbor issues
- **HPA + PDB**: Consumer-lag-based autoscaling + pod disruption budgets
- **Monitoring**: Prometheus alert rules + Grafana dashboards + Kustomize overlays

### Phase 3: Real-Time Data Pipeline

End-to-end data processing pipeline handling 60K+ events/sec:

- **8 Kafka topics** with AVRO schemas, 3-way replication, strategic partitioning (12 partitions for high-throughput topics)
- **4 stream processors**: Traffic Optimizer (<100ms SLO), Anomaly Detector, Energy Optimizer, Data Broker (anonymization engine)
- **Kafka Connect S3 sink**: 4 connectors archiving raw data to S3 data lake
- **Schema Registry**: Backward/forward compatibility control
- **Dead Letter Queue**: Failed message capture, classification, and retry
- **IAM auth**: Zero-secret Kafka access — each pod inherits permissions via IRSA

---

## Key Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| MSK Express over Provisioned Standard | 3x throughput, 20x faster scaling, 90% faster recovery, auto-scaling storage |
| MSK Serverless for dev | $0 idle cost, pay-per-use, no cluster management |
| Aurora PostgreSQL over standard RDS | ~30s failover vs ~120s, auto-scaling to 128 TB |
| IAM Access Control over mTLS | No certificate rotation, IRSA for pod-level auth, port 9098 |
| 3-AZ deployment | Required for MSK Express; maps to Woven City redundancy |
| CloudWatch + Prometheus split | Terraform manages infra monitoring; Prometheus/Grafana in K8s (Phase 2) |
| KMS single CMK per environment | Simplified key management, cross-service audit trail |
| 4 S3 buckets with lifecycle policies | Cost optimisation: 30d Standard → Glacier → delete |

---

## Infrastructure Scale

| Dimension | Value |
|-----------|-------|
| Events/sec | 60,000+ |
| Connected devices | 10,000+ |
| Microservices | 50+ internal + inventor |
| Kafka throughput | ~60 MBps (3× express.m7g.xlarge) |
| Database storage | 128 TB auto-scaling (Aurora) |
| S3 data lake | Multi-petabyte, 7-year lifecycle |
| Availability target | 99.95% (~4.38 hours/year) |
| Recovery targets | RPO 5 min, RTO 15 min |

---

## Estimated Monthly Cost (Production)

| Service | Configuration | Est. Cost |
|---------|--------------|-----------|
| MSK Express | 3 × express.m7g.xlarge | ~$4,500 |
| EKS | 8 × m7g.xlarge on-demand | ~$8,000 |
| Aurora | r6g.xlarge + 2 readers | ~$2,500 |
| S3 | 50 TB + lifecycle | ~$600 |
| Other | NAT GW, CloudWatch, KMS | ~$600 |
| **Total** | | **~$16,200/month** |

---

## Competitive Advantages

1. **Modular by design**: Teams provision environments by editing `terraform.tfvars` — no Terraform expertise needed
2. **Zero-secret Kafka**: IAM auth via IRSA means no passwords to manage, rotate, or leak
3. **Multi-layer autoscaling**: MSK Express (broker), Karpenter (node), HPA (pod), Aurora (compute+storage) — each layer scales independently
4. **Built-in multi-tenancy**: Network policies, RBAC, resource quotas, and data broker anonymization create defense-in-depth for external inventors
5. **Interview-ready**: Complete, production-quality infrastructure that demonstrates deep systems thinking across networking, security, data pipelines, reliability, and cost

---

## What This Enables

| City Service | Enabled By |
|-------------|-----------|
| Real-time traffic optimization | Stream processor + MSK (<100ms) |
| Autonomous vehicle coordination | MSK low-latency + Aurora device registry |
| Energy management (15% savings) | Stream processor + Timestream |
| External inventor ecosystem | Multi-tenancy + data broker |
| Safety & emergency response | MSK priority topics + P99 <100ms SLO |
| City analytics | S3 data lake + Athena/Spark |

---

## Relevant Links

- `docs/BACKGROUND.md` — Woven City context and problem statement
- `docs/ARCHITECTURE.md` — Detailed architecture documentation
- `docs/DEPLOYMENT.md` — Step-by-step deployment guide
- `docs/SCALING.md` — Scaling strategies across all layers
- `docs/DISASTER-RECOVERY.md` — DR procedures with RPO/RTO targets
- `docs/TROUBLESHOOTING.md` — Common issues and diagnostic procedures
- `docs/IMPLEMENTATION-PLAN.md` — Phase-by-phase build plan
- `docs/OPERATIONS.md` — Day-2 operations guide
- `docs/SECURITY.md` — Security architecture and best practices
- `diagrams/` — SVG architecture diagrams (high-level, AWS infra, data flow, latency timeline)
