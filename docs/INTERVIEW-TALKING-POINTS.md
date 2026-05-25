# Agora Platform — Interview Talking Points

**Role**: Platform Engineer @ Woven City / Toyota Woven  
**Interview**: May 26/27, 2026 — Anna Zyrina (Senior DevOps) + Melvin Dvaz (Senior SRE)  
**Strategy**: Every answer anchored to actual code. Pull up file on screen. Point to line.

---

## HOW TO USE THIS DOC

1. Interviewer asks question → jump to that section
2. Open the referenced file in your editor during answer
3. Lead with the headline, then show the code
4. End with trade-offs + metrics

---

## Q1: "Walk me through your infrastructure design for Agora"

**Headline**: "I built a 3-tier AWS infrastructure on EKS in ap-northeast-1, using modular Terraform with separate modules for each concern."

**Show**: `agora-infrastructure/terraform/` tree

```
terraform/
├── modules/
│   ├── vpc/         ← networking foundation
│   ├── eks/         ← Kubernetes cluster
│   ├── msk/         ← Kafka (Amazon MSK)
│   ├── rds/         ← Aurora PostgreSQL
│   ├── s3/          ← data lake
│   ├── iam/         ← least-privilege roles
│   ├── kms/         ← encryption keys
│   ├── monitoring/  ← observability stack
│   └── kubernetes-addons/  ← EBS CSI, CoreDNS, etc.
├── environments/
│   ├── dev/
│   ├── staging/
│   └── production/
```

**Key design decisions to explain**:
- Single cluster for Woven City (one location) — complexity of multi-cluster not justified yet
- All modules are reusable and parameterized — non-infra teams can provision environments
- Region: `ap-northeast-1` (Tokyo) — data sovereignty + latency to Woven City site
- State in S3 + DynamoDB lock: `agora-infrastructure/terraform/environments/production/main.tf:2-10`

---

## Q2: "How do you handle 60K events/sec from 10,000+ IoT devices?"

**Headline**: "Kafka (Amazon MSK) as the ingestion backbone. Partitioned by device type, 3x replication, Snappy compression, async stream processors."

**Show**: `agora-data-pipeline/kafka-topics/definitions.yaml`

Key numbers to cite:
```yaml
# Line 2-9: vehicle.telemetry — highest volume topic
partitions: 12          # 12 partitions = 12 parallel consumers max
replication_factor: 3   # survives 1 broker failure
compression.type: snappy  # ~60% size reduction
min.insync.replicas: 2   # write fails only if 2+ brokers down
```

**Partitioning rationale** (say this out loud):
- `vehicle.telemetry`: 12 partitions — highest throughput, needs parallel processing
- `signal.events`: 6 partitions — moderate volume, traffic signal commands
- `incidents`: 1 partition — low volume, needs strict ordering for audit trail

**Show processor**: `agora-data-pipeline/stream-processors/traffic-optimizer/processor.py:238-252`
```python
msgs = self.consumer.consume(num_messages=100, timeout=1.0)  # batch consume
self.consumer.commit(asynchronous=True)  # async commit for throughput
self.producer.poll(0)  # non-blocking produce
```

**Follow-up: "What if a Kafka broker goes down?"**
- MSK: 3 brokers, `replication_factor: 3`, `min.insync.replicas: 2`
- Producer write succeeds as long as 2/3 brokers ack
- Consumer rebalances to remaining brokers automatically
- Code: `agora-data-pipeline/stream-processors/traffic-optimizer/processor.py:66-88` — consumer config handles rebalance

**Follow-up: "Device data arrives 5 minutes late?"**
- Kafka retains data: `retention.ms: 604800000` (7 days)
- Stream processors can replay from offset
- DLQ for unprocessable messages: `agora-data-pipeline/dead-letter-queue/dlq-processor.py`

---

## Q3: "How do you design multi-tenancy for external inventors?"

**Headline**: "Namespace-level isolation with RBAC, ResourceQuota, and NetworkPolicy. Inventors get their own namespace with hard CPU/memory caps. Default-deny network policy blocks cross-namespace traffic."

**Show in order**:

**1. Namespace isolation**
- `agora-kubernetes-components/kustomization/base/namespaces/inventors.yaml`
- `agora-kubernetes-components/kustomization/base/namespaces/city-services.yaml`
- Separate namespaces = separate RBAC, quotas, network boundaries

**2. ResourceQuota — prevents noisy neighbor**
- `agora-kubernetes-components/kustomization/base/resource-quotas/inventors-quota.yaml:8-11`
```yaml
requests.cpu: "4"
requests.memory: "8Gi"
limits.cpu: "8"
limits.memory: "16Gi"
```
"Inventors are hard-capped at 4 CPU requests. City services are isolated from resource exhaustion."

**3. RBAC — least privilege**
- `agora-kubernetes-components/kustomization/base/rbac/inventors-role.yaml`
- Inventors can CRUD their own pods/services/deployments
- Cannot touch city-services namespace (no ClusterRole)

**4. NetworkPolicy — default deny**
- `agora-kubernetes-components/kustomization/base/network-policies/default-deny-all.yaml`
- Applied to all 3 namespaces: city-services, inventors, monitoring
- Explicit allow rules per namespace: `inventors-allow.yaml`, `city-services-allow.yaml`

**5. Data anonymization before inventor access**
- `agora-data-pipeline/stream-processors/data-broker/transformations/anonymizer.py:7-16`
```python
PII_FIELDS = {"driver_id", "driver_name", "license_plate", "payment_info", ...}
# GPS rounded to 2 decimal places (~1km precision)
def _round_gps(value: float) -> float:
    return round(value, 2)
```
"Inventors never see raw PII. Vehicle IDs stripped, GPS precision reduced to ~1km."

**Follow-up: "Inventor API hammers traffic service?"**
- NetworkPolicy blocks cross-namespace traffic by default
- ResourceQuota caps inventor CPU/memory
- Rate limiting at API Gateway: `agora-kubernetes-components/kustomization/base/services/api-gateway/`

---

## Q4: "Walk me through your Terraform module design"

**Headline**: "Each module is single-responsibility, parameterized, and environment-agnostic. Same module runs dev, staging, production with different var files."

**Key design patterns**:

**VPC module** — `agora-infrastructure/terraform/modules/vpc/main.tf`
```hcl
# Line 2: dynamic multi-AZ — NOT hardcoded
az_count = length(var.availability_zones)

# Line 36-43: one NAT gateway per AZ for HA
resource "aws_nat_gateway" "main" {
  count = local.az_count  # 3 in prod, 1 in dev (cost trade-off)
}

# Lines 53, 68, 82: subnets span all AZs
availability_zone = var.availability_zones[count.index]
```
"If we pass 3 AZs in prod, we get 3 NAT gateways, 3 public, 3 private, 3 DB subnets automatically."

**EKS module** — `agora-infrastructure/terraform/modules/eks/main.tf`
```hcl
# Line 76-77: API endpoint private-only
endpoint_private_access = true
endpoint_public_access  = false

# Line 307: OIDC provider for IRSA
# → pods get scoped IAM roles, no node-level credentials
```

**MSK module** — `agora-infrastructure/terraform/modules/msk/main.tf:64,78`
```hcl
instance_type   = var.instance_type  # parameterized
encryption_in_transit {              # TLS enforced
```

**State management** — `agora-infrastructure/terraform/environments/production/main.tf:2-10`
```hcl
backend "s3" {
  bucket         = "agora-terraform-state"
  key            = "production/terraform.tfstate"
  region         = "ap-northeast-1"
  encrypt        = true
  dynamodb_table = "terraform-lock"  # prevents concurrent applies
}
```

**Trade-off to mention**:
"I chose Terraform modules over Terragrunt for simplicity — one less abstraction layer. If the module count grows past ~15, I'd reconsider Terragrunt for DRY environment configs."

---

## Q5: "Disaster recovery strategy?"

**Headline**: "Multi-AZ everywhere at the infrastructure layer. Kafka replication across 3 brokers. RDS Aurora with configurable read replicas and 7-day backup. Stateless K8s workloads — kill and reschedule."

**Infrastructure HA**:
- VPC: 3 AZs, private/public/DB subnets in each
  - `agora-infrastructure/terraform/modules/vpc/main.tf:2` → `az_count = length(var.availability_zones)`
- EKS nodes: spread across AZs via node group
- MSK: 3 brokers, 3 AZs, `replication_factor: 3`
  - `agora-infrastructure/terraform/modules/msk/main.tf:120` → `default.replication.factor = 3`

**Database HA**:
- Aurora: `rds/main.tf:71-75` — `backup_retention_period`, `storage_encrypted = true`
- `multi_az = var.multi_az` — enabled for production
- Read replicas: `rds/main.tf:127+`
- Backup window: `03:00-04:00` (low traffic)

**Kafka DR**:
- Data retained 7 days: can replay from any point
- `min.insync.replicas: 2` — survives 1 broker failure with no data loss
- DLQ captures failed processing for reprocessing

**K8s workload DR**:
- `agora-kubernetes-components/kustomization/base/services/traffic-optimizer/pdb.yaml:9`
  → `minAvailable: 1` — PDB prevents all pods going down during maintenance
- `hpa.yaml:13-14` → `minReplicas: 2` — always 2 pods minimum

**RTO/RPO estimates to state**:
- EKS pod failure: RTO ~30 seconds (K8s reschedule)
- Kafka broker failure: RTO ~0 (automatic leader election)
- RDS failover: RTO ~60-120 seconds (Aurora automatic failover)
- Full AZ failure: RTO ~5 minutes (nodes reschedule to other AZs)

---

## Q6: "How do you monitor this at scale?"

**Headline**: "Three-pillar observability: Prometheus (metrics) + Loki (logs) + Alertmanager (routing). Prometheus Operator makes Phase 2+3 ServiceMonitors and PrometheusRules actually work. Alertmanager routes 22 alerts to Slack or PagerDuty based on severity."

**Show stack**: `agora-observability/kustomization/base/`

**The key architectural point — Prometheus Operator:**

> "Phases 2 and 3 wrote all their ServiceMonitors and PrometheusRules using `monitoring.coreos.com/v1` CRDs. Without the Operator, those are just inert YAML — Prometheus doesn't read them. The Operator watches those CRDs and auto-reconciles the Prometheus scrape config. When a new service adds a ServiceMonitor, Prometheus discovers it automatically. Zero manual config edits."

Show: `agora-observability/kustomization/base/prometheus-operator/operator-deployment.yaml`
```yaml
--namespaces=""   # watches ALL namespaces — critical for picking up city-services ServiceMonitors
```

**Alert routing:**
```
22 alerts total:
  critical → PagerDuty (immediate, repeat 2h)
  warning  → Slack #agora-alerts (groupWait 30s, repeat 4h)
  info     → null (suppressed)

groupBy: [alertname, severity, namespace]
```

Show: `agora-observability/kustomization/base/alertmanager/alertmanager-config.yaml`

**Log aggregation with Loki:**

> "Loki uses the same label model as Prometheus — namespace, pod, service. In Grafana Explore, I can see a spike in `ProcessingErrorRateHigh` metric and jump directly to the logs for that pod in the same time window. That correlated investigation is the key reason I chose Loki over Elasticsearch."

Show: `agora-observability/kustomization/base/loki/loki-configmap.yaml`
```yaml
retention_period: 720h    # 30 days
storage: S3 (agora-{env}-app-logs/loki/ — Phase 1 bucket, no new infra)
```

**Exporters complete the picture:**
- `node-exporter` DaemonSet → host CPU/mem/disk metrics (feeds NodeHighMemory, DiskPressure alerts)
- `kube-state-metrics` → K8s object state (feeds NodeNotReady, PodOOMKilled, DeploymentReplicasMismatch)
- `kafka-exporter` → consumer lag (feeds ConsumerLagHigh — but **important caveat**)

**MSK + kafka-exporter limitation (know this cold):**
> "The Go Kafka client doesn't support MSK's IAM auth (`SASL_IAM`). Workaround: `amazon/aws-signing-proxy` sidecar. It listens on localhost:9092, proxies to MSK broker:9098 with SigV4 signatures. kafka-exporter connects to localhost — it never touches IAM auth. In production I'd also use MSK CloudWatch's `MaxOffsetLag` metric (already wired in Phase 1) as a fallback."

Show: `agora-observability/kustomization/base/exporters/kafka-exporter-deployment.yaml`

**AMP remote_write:**
> "Phase 1 provisioned an Amazon Managed Prometheus workspace but nothing wrote to it. Phase 4 adds a `remote_write` block to Prometheus with sigv4 IRSA auth. Local retention is 90 days; AMP extends that indefinitely for compliance queries."

**4 Grafana dashboards (all provisioned via ConfigMap):**
1. Kubernetes Overview — cluster CPU/mem, pod phases, container restarts, HPA pressure
2. Agora Pipeline — consumer lag, throughput, P99 latency, DLQ accumulation
3. Node Exporter — per-node CPU/mem/disk/network
4. Loki Logs — error rate by service, log volume, recent errors

**Trade-off to nail:**
"Loki vs Elasticsearch: Loki indexes labels only, not raw log content. That means 10x lower storage cost and no Elasticsearch cluster to manage. Trade-off: less powerful full-text search. For our use case — structured JSON logs labeled by service and namespace — Loki's LogQL is sufficient."

---

## Q7: "Single cluster or multi-cluster for Woven City?"

**Headline**: "Single cluster for current phase. Woven City is one physical location, so network partitions between clusters add complexity without availability benefit. Designed for multi-cluster expansion."

**Current design**:
- Single EKS cluster in `ap-northeast-1`
- Namespace isolation handles tenant separation (city-services / inventors)
- RBAC + NetworkPolicy provide security boundaries within cluster

**Why NOT multi-cluster now**:
- Woven City = one site → multi-cluster = distributed system problems without distributed benefits
- No need for cross-region data sovereignty yet
- Consistent etcd state is simpler for traffic-critical safety systems

**When I'd go multi-cluster**:
- Second Woven City site opens
- Compliance requires data in different regions
- SLO targets require independent blast radius

**Show**: `agora-infrastructure/terraform/modules/eks/main.tf:76-77`
```hcl
endpoint_private_access = true
endpoint_public_access  = false
```
"Control plane is private-only — can extend to cluster mesh (Cilium/Istio) when needed."

---

## Q8: "How does your stream processing handle real-time safety-critical data?"

**Headline**: "Safety-critical signals (traffic control) processed first, with separate topics and dedicated consumer groups. Anomaly detection runs in parallel, not in the critical path."

**Show traffic processor**: `agora-data-pipeline/stream-processors/traffic-optimizer/processor.py`
- Batch consume for throughput: line 238
- Async commit: line 251 — does not block processing
- Dedicated Kafka producer with `batch.size: 65536`: line 90

**Show anomaly detector**: `agora-data-pipeline/stream-processors/anomaly-detector/detector.py`
- Prometheus metrics: lines 36-50 (Counter, Gauge, Histogram)
- IAM auth for MSK: `AWS_MSK_IAM_ENABLED` env var
- Model-based anomaly detection with `ANOMALY_THRESHOLD`

**Data flow**:
```
IoT Device
  → MSK vehicle.telemetry (12 partitions)
  → traffic-optimizer (consumer group: traffic-optimizer-group)
     → signal.commands (traffic light changes)
  → anomaly-detector (consumer group: anomaly-detector-group)
     → incidents topic (alerts)
  → data-broker (consumer group: data-broker-group)
     → data.anonymized.vehicle (inventor-accessible)
```

**Key design**: consumer groups are independent → anomaly detection never slows traffic control

---

## Q9: "Walk me through your Kubernetes deployment strategy"

**Headline**: "Kustomize with base + environment overlays. Production gets strict anti-affinity, higher replicas, and different resource limits — all via patches, not code duplication."

**Show kustomize structure**:
```
kustomization/
├── base/          ← single source of truth for all resources
└── overlays/
    ├── development/   ← reduced replicas, relaxed limits
    ├── staging/       ← mid-scale
    └── production/    ← strict anti-affinity + scaled replicas
```

**Show production patches**: `agora-kubernetes-components/kustomization/overlays/production/patches/`
- `scale-traffic-optimizer.yaml` — bump replicas
- `strict-anti-affinity.yaml` — force pods onto different nodes
- Each patch targets specific fields, base manifest unchanged

**Zero-downtime deployment**:
- `PDB minAvailable: 1` → rolling update never kills all pods
- `HPA min=2 max=10` → always redundant, scales on demand
- `RollingUpdate` strategy in deployments

---

## Q10: "How do you enforce least-privilege IAM?"

**Headline**: "IRSA (IAM Roles for Service Accounts). Each service gets a scoped IAM role. No node-level credentials. Roles defined in Terraform IAM module."

**Show**:
- `agora-infrastructure/terraform/modules/eks/main.tf:307` — OIDC provider enables IRSA
- `agora-infrastructure/terraform/modules/iam/main.tf` — per-service IAM roles
- `agora-kubernetes-components/kustomization/base/services/traffic-optimizer/sa.yaml` — ServiceAccount with role annotation

**Why IRSA over node IAM**:
- Node IAM = all pods on node share credentials = blast radius = entire node
- IRSA = pod gets token scoped to specific S3 bucket or MSK cluster
- Token auto-rotates, no secret management needed

**KMS for encryption**:
- `agora-infrastructure/terraform/modules/kms/main.tf` — CMK per environment
- Used for: S3 SSE-KMS, EBS volumes, MSK at-rest encryption
- Key rotation enabled: `enable_key_rotation = true`

---

---

## Q11: "How does log aggregation work? How do you correlate logs with metrics?"

**Headline**: "Promtail DaemonSet ships logs from all pods to Loki. Same label model as Prometheus — namespace/pod/service. In Grafana, split-pane view shows metric spike + pod logs in the same time window."

**Promtail pipeline** (show: `agora-observability/kustomization/base/promtail/promtail-configmap.yaml`):
```yaml
Pipeline stages:
1. cri: {}              # parse containerd CRI log format (not raw JSON)
2. json: {level, msg}   # extract structured fields
3. labels: {level}      # promote level to Loki label
4. labeldrop: [filename] # drop high-cardinality label (cardinality kills Loki perf)
5. match: drop /healthz  # suppress istio-proxy health check noise
```

**Why drop filename?** Loki indexes labels. High-cardinality labels (one per file path = thousands) bloat the index and slow queries. Keep labels to service/namespace/pod/level.

**Correlation flow:**
```
Grafana: Agora Pipeline dashboard
  → ConsumerLagHigh alert fires at 14:32
  → Click pod in "Consumer Lag by Group" panel
  → Grafana Explore splits: left = Prometheus metric, right = Loki logs
  → Query: {namespace="city-services", pod=~"data-broker.*"} |= "error"
  → See: "Schema deserialization failure" at 14:30 — root cause in 30 seconds
```

**Loki storage architecture** (be ready to explain):
- Hot path: WAL + index on PVC (`/loki/index`)
- Cold path: log chunks compressed → S3 (`agora-{env}-app-logs/loki/`)
- Retention: 30 days enforced by compactor
- Schema: tsdb v12 — faster label queries than the older boltdb-shipper

---

## Q12: "How do you handle alerting without alert fatigue?"

**Headline**: "Severity tiers: critical wakes someone up, warning goes to Slack for next-business-day review, info is suppressed. Grouping prevents duplicate notifications."

**Routing logic** (show: `agora-observability/kustomization/base/alertmanager/alertmanager-config.yaml`):
```
groupBy: [alertname, severity, namespace]
  → Multiple pods in city-services all fail → ONE notification, not 10

groupWait: 30s    → buffer before first notification (catch alert clusters)
groupInterval: 5m → how long to wait to add new alerts to existing group
repeatInterval: 4h (warning), 2h (critical) → how often to re-notify if unresolved
```

**What makes a good alert rule:**
- Alert on SLO violations, not symptoms: `TrafficOptimizerLatencyBreach` (P99>100ms) not `high CPU`
- `for: 5m` avoids flapping on transient spikes
- `runbook` annotation on every alert → runbook URL embedded in PagerDuty incident description

**Test alerting** (show: `agora-observability/scripts/test-alerts.sh`):
```bash
./scripts/test-alerts.sh
# Posts TestCriticalAlert → verify PagerDuty incident created
# Posts TestWarningAlert  → verify Slack #agora-alerts message
# Posts TestInfoAlert     → verify nothing received (blackhole)
```

**22 total alerts — explain the coverage pyramid:**
- 8 K8s system (infra health: nodes, OOM, disk, memory)
- 4 application SLOs (latency + error rate per service)
- 10 pipeline (consumer lag, DLQ, throughput, Kafka Connect)

---

## QUICK METRICS CARD

Memorize these numbers. Cite them confidently.

| Metric | Value | Source |
|--------|-------|--------|
| IoT devices | 10,000+ | system design |
| Events/sec | 60,000 | design target |
| vehicle.telemetry partitions | 12 | `kafka-topics/definitions.yaml:3` |
| Kafka replication factor | 3 | `definitions.yaml:4` |
| Traffic optimizer P99 SLO | <100ms | `prometheus-rules.yaml:11` |
| Error rate SLO | <0.1% | `prometheus-rules.yaml:19` |
| HPA max replicas | 10 | `hpa.yaml:14` |
| RDS backup retention | configurable (7 days prod) | `rds/main.tf:71` |
| Kafka data retention | 7 days | `definitions.yaml:7` |
| Inventor CPU quota | 4 CPU req / 8 CPU limit | `inventors-quota.yaml:8,10` |
| EKS API endpoint | private only | `eks/main.tf:76-77` |
| Total infra code | 8,263 lines | repo |
| **Phase 4 — Observability** | | |
| Prometheus retention | 90d (prod) / 30d (dev) | `prometheus.yaml` overlay patches |
| Loki retention | 30 days | `loki-configmap.yaml` limits_config |
| Total alert rules | 22 (8 K8s + 4 app + 10 pipeline) | `alert-rules/` |
| Alertmanager groupWait | 30s | `alertmanager-config.yaml` |
| Alertmanager repeatInterval | 2h (critical) / 4h (warning) | `alertmanager-config.yaml` |
| Grafana dashboards | 4 | `grafana/dashboards/` |
| kafka-exporter auth workaround | aws-signing-proxy sidecar | `kafka-exporter-deployment.yaml` |

---

## TRADE-OFFS CHEAT SHEET

Always offer a trade-off. Shows senior thinking.

| Decision | Alternative considered | Why this choice |
|----------|----------------------|-----------------|
| Kafka (MSK) over SQS/Kinesis | SQS: simpler ops | Need replay, consumer groups, exactly-once semantics |
| Single cluster over multi-cluster | Multi: better blast radius | Woven City = 1 site, complexity not justified yet |
| Terraform modules over Terragrunt | Terragrunt: DRYer | Fewer abstractions, easier for new team members |
| Kustomize over Helm | Helm: richer templating | Less abstraction, plain YAML, easier to audit |
| Namespace isolation over vCluster | vCluster: harder isolation | vCluster = operational complexity; namespaces sufficient for Woven City tenant count |
| Prometheus+Grafana over Datadog | Datadog: less ops | Cost control at city scale; open source = no vendor lock-in |
| NAT per AZ over shared NAT | Single NAT: ~$90/mo savings | Single NAT = SPOF; outage in that AZ = no internet for private subnets |
| IRSA over node IAM | Node IAM: simpler setup | Pod-level credential scope; node compromise ≠ all-bucket access |
| Prometheus Operator over vanilla | Vanilla: simpler | Phases 2+3 ServiceMonitors/PrometheusRules are inert without Operator |
| Loki over Elasticsearch | Elasticsearch: richer full-text search | 10x lower storage cost, same label model as Prometheus, no cluster ops |
| aws-signing-proxy sidecar for kafka-exporter | JVM-based exporter | Go kafka-exporter doesn't support SASL_IAM; sidecar avoids rewrite |

---

## OPENING NARRATIVE (60 seconds)

Deliver this at the start before they ask questions:

> "I designed Agora as a platform for Woven City's IoT infrastructure — 10,000+ devices streaming real-time data from vehicles, environmental sensors, and traffic signals. The core challenge was supporting two very different workload profiles: city-critical services that need <100ms latency for safety operations, and external inventor APIs that need access to anonymized data without being able to impact city systems.
>
> I structured this as three layers: Terraform for the AWS foundation, Kubernetes for workload orchestration, and Kafka for real-time data. Each layer has a clear boundary. Let me walk you through the repo."

Then open `agora-infrastructure/terraform/` and start with the VPC module.

---

## IF THEY ASK ABOUT SOMETHING NOT IN THE REPO

"I haven't built that yet, but here's how I'd design it..."

- **Service mesh (Istio)**: See Q13 — full Istio mTLS answer for the trusted/untrusted boundary question.
- **GitOps/ArgoCD**: "Deployment pipeline would use ArgoCD pointing at the kustomize overlays. Each merge to main auto-syncs to staging."
- **Cost optimization**: "Spot instances for non-critical workloads (data processing), on-demand for city-critical. Karpenter for node autoprovisioning."
- **Secret management**: "Currently using K8s Secrets. Next step: External Secrets Operator + AWS Secrets Manager for rotation."
- **Distributed tracing**: "Not built yet — Phase 5. Would add Tempo (Grafana's tracing backend) + OpenTelemetry Collector as a DaemonSet. OTel SDK in each service with OTLP exporter. Grafana already has Tempo datasource support — traces would correlate with the existing Prometheus metrics and Loki logs in the same dashboard."
- **Logging already built (Phase 4)**: Loki + Promtail. See Q11.
- **Alerting already built (Phase 4)**: Alertmanager with Slack/PagerDuty routing. See Q12.

---

## Q13: "How would you use Istio for mTLS between trusted city infra and unverified third-party apps?"

*(Anna, DevOps — JD explicitly lists Istio. This WILL be asked.)*

**Headline**: "Namespace boundary + PeerAuthentication STRICT + AuthorizationPolicy deny-by-default. City infra is a zero-trust perimeter; third-party apps get mTLS identity but not access."

**The model:**

```
agora-system namespace       agora-inventors namespace
(city services)              (third-party apps)
PeerAuthentication: STRICT   PeerAuthentication: STRICT
                             AuthorizationPolicy: deny all
                             except explicitly listed city APIs
```

**Layer 1 — Enforce mTLS cluster-wide:**
```yaml
# Every pod gets a SPIFFE X.509 cert from istiod (cert rotated every 24h)
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: agora-system
spec:
  mtls:
    mode: STRICT   # reject any plaintext connection into this namespace
```
Same applied to `agora-inventors` namespace. Both sides have TLS identity; Istio's Citadel issues certs automatically.

**Layer 2 — AuthorizationPolicy on city services:**
```yaml
# city-traffic-optimizer only accepts calls from known city service accounts
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: traffic-optimizer-policy
  namespace: agora-system
spec:
  selector:
    matchLabels:
      app: traffic-optimizer
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - "cluster.local/ns/agora-system/sa/emergency-router"
        - "cluster.local/ns/agora-system/sa/city-dashboard"
        # third-party apps: NOT listed → denied by default
```

**Layer 3 — Egress control for third-party apps:**
```yaml
# Third-party apps can only call explicitly registered external endpoints
# Default Istio egress: REGISTRY_ONLY — blocks all unlisted outbound
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: inventors-allowed-egress
  namespace: agora-inventors
spec:
  hosts:
  - api.agora.woven-city.global   # only the Agora public API
  ports:
  - number: 443
    name: https
```

**Layer 4 — Traffic routing for canary/safety:**
```yaml
# VirtualService: 95% stable, 5% new version of traffic-optimizer
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: traffic-optimizer
spec:
  http:
  - route:
    - destination:
        host: traffic-optimizer
        subset: stable
      weight: 95
    - destination:
        host: traffic-optimizer
        subset: canary
      weight: 5
```

**Key talking points:**
- Istio mTLS = SPIFFE/SVID certs. Each pod identity = `spiffe://cluster.local/ns/<namespace>/sa/<serviceaccount>`. Cert auto-rotated every 24h by istiod.
- `STRICT` mode rejects plaintext — a misconfigured third-party app that doesn't have an Envoy sidecar can't even reach a city service, regardless of network policy.
- `AuthorizationPolicy` deny-by-default: city services only accept calls from explicitly named service account principals. A new third-party app gets mTLS identity automatically but zero access until explicitly granted.
- Egress gateway: third-party apps' outbound traffic goes through an `EgressGateway` — visibility, logging, and a choke point to block unexpected outbound calls.
- "I haven't deployed Istio in Agora yet (NetworkPolicy handles L4 today), but the namespace + PeerAuthentication + AuthorizationPolicy pattern is the standard extension path I'd follow."

**If asked "Why Istio over Cilium?":**
> "Cilium is excellent for L3/L4 and eBPF-based observability. For the third-party trust boundary specifically — where I need L7 AuthorizationPolicy with service account principals, circuit breaking, and canary traffic splitting — Istio's control plane is more mature. Cilium doesn't have `AuthorizationPolicy` with SPIFFE principals. In a safety-critical city platform, I want explicit L7 allow-lists, not just network segmentation."

---

## Q14: "How do you define SLOs for a CUJ where software interacts with physical reality?"

*(Melvin, SRE — the Woven City differentiator question. Emergency routing, smart locks, power grids.)*

**Headline**: "The error budget model breaks at safety thresholds. Two-tier SLO: physical-safety paths get 99.999% with zero error budget tolerance; non-critical paths get standard SLO math."

**The core insight:**
Traditional SLO: 99.9% availability → 43 min/month error budget. Acceptable for a web app.

For emergency assistance: saying "43 minutes of failure per month is acceptable" means in the worst case, a citizen calling for emergency help gets no response for 43 minutes. That's not an engineering trade-off — that's a liability and a human safety failure. The error budget model doesn't apply.

**Two-tier approach:**

| CUJ Tier | Example | SLO | Alert model |
|---|---|---|---|
| Safety-critical | Emergency call routing, automatic door unlock for evacuation | 99.999% (< 5 min/year) | ANY error → immediate page. No burn rate, no grouping. |
| City-operational | Traffic signal coordination, parking availability | 99.9% (43 min/month) | Burn rate alerting, error budget math |
| Convenience | Ambient sensor dashboard, weather display | 99.5% | Warning-only alerts |

**For safety-critical CUJs, design changes:**
- No error budget to burn → alert on the first error, not on rate
- Redundant paths: the emergency routing service has a warm standby that takes over in < 1s (not HPA scale-up — that takes 30-60s)
- Graceful degradation: if the digital system fails, physical fallback is always available (manual override, phone backup)
- SLI is end-to-end: not "service responds 200 OK" but "emergency responder is dispatched within 60 seconds of citizen request"

**SLI definition for emergency CUJ:**
```
SLI = successful_emergency_dispatches / total_emergency_requests
where "successful" = responder dispatched within 60s AND citizen acknowledged

# NOT: HTTP 200 rate (that's just "the API responded")
# YES: end-to-end: request received → responder on route
```

**For Melvin follow-up "How do you test this without risking a real emergency?":**
- Synthetic monitoring: synthetic emergency requests routed to a shadow stack that exercises the full path but writes to a test table
- Game days: quarterly tabletop exercises — walk the runbook without triggering real dispatch
- Chaos in staging only: Chaos Mesh fault injection on the staging replica of emergency routing; never in production for safety-critical paths
- Dark launches: new code runs in parallel processing real traffic, but response only served from old code until validation passes

---

## Q15: "What does DR look like for Agora? How do you test it without disrupting residents?"

*(Extends the existing Q5 DR answer — they will ask the testing follow-up)*

**Architecture (already in Q5):** Multi-AZ, MSK replication.factor=3, Aurora multi-AZ, stateless K8s.

**Testing — the hard part:**

**1. Game days (quarterly):**
Structured exercises where on-call team walks through a simulated failure. No actual infrastructure changes — tabletop. Document gaps in runbooks. Cheap, low-risk, high-value for runbook accuracy.

**2. Staged chaos (staging environment):**
AWS Fault Injection Simulator or Chaos Mesh on the staging cluster:
- Terminate one AZ's worth of EKS nodes → verify HPA and pod rescheduling
- Inject MSK broker failure → verify `min.insync.replicas=2` holds, consumers reconnect
- Simulate RDS primary failure → verify Aurora failover completes < 30s

Run monthly. Never on production for city services.

**3. Production DR drills (non-critical paths only):**
For services where impact is low (ambient sensor ingestion, not emergency routing):
- Intentionally drain one AZ's nodes during low-traffic window
- Measure actual RTO/RPO vs. targets
- We did this at Rakuten post-incident — intentionally drained a node during the settlement window in staging to verify the PDB fix actually worked before trusting it in production

**4. Synthetic canaries:**
Production synthetic transactions that test the full path. If the canary fails, it fires a real alert before a real citizen is impacted.

**RTO/RPO targets:**
| Service tier | RTO | RPO |
|---|---|---|
| Safety-critical | < 30 seconds | 0 (synchronous replication) |
| City-operational | < 5 minutes | < 1 minute (MSK retention) |
| Convenience | < 30 minutes | < 7 days (Kafka retention) |

---

## Q16: "Cost engineering example — tools used, waste found, how optimized?"

*(JD responsibility: "perform cost engineering, identify optimization opportunities, own capacity planning")*

**Headline**: "Cost attribution first — you can't optimize what you can't measure. Kubecost for per-namespace, per-workload cost. AWS Cost Explorer for service-level. Then: right-size, then Spot, then Reserved."

**Rakuten example:**

At Rakuten, I noticed MSK broker costs were the second-largest line item. Used AWS Cost Explorer to see that dev and staging were running `kafka.m5.2xlarge` brokers — same instance family as production. Dev consumed < 5% of production throughput.

Steps:
1. AWS Cost Explorer: identify MSK as $2,400/month (dev+staging combined)
2. CloudWatch MSK metrics: peak throughput in dev = 200 msg/sec. `kafka.m5.large` handles 2,000+ msg/sec — 10x headroom.
3. Changed dev/staging to `kafka.m5.large` via Terraform module variable change (1-line PR)
4. Savings: ~$1,100/month, $13,200/year

For Agora, the approach:
```
Tool           | What it shows
---------------|------------------------------------------
Kubecost       | Per-namespace cost. inventor namespace
               | vs agora-system. Charge-back to teams.
AWS Cost       | Service-level: MSK, EKS, RDS, S3 spend
Explorer       | over time. Spot for data pipeline workers.
Compute        | Right-size EC2/EKS node recommendations
Optimizer      | based on actual CPU/memory utilization.
```

**Spot instances for pipeline workers:**
Agora's data pipeline workers (Phase 3 stream processors) are stateless and Kafka-backed — if a Spot node is reclaimed, the consumer group rebalances and another pod picks up the partition. Safe for Spot. ~70% cost reduction on those workers.

**Reserved instances for steady-state:**
EKS nodes for city-critical services: 3-year Reserved Instance (RI) for ~35% savings vs on-demand. Predictable baseline load.

**Capacity planning for unpredictable growth:**
- Define trigger thresholds: "when 3-month avg CPU utilization crosses 70%, provision next tier"
- Event-based pre-provisioning: Woven City will add districts. Pre-provision at district announcement, not at district opening.
- Karpenter for node autoprovisioning: instead of fixed node groups, Karpenter provisions the right instance type for the workload. Cheaper + faster than pre-provisioned fixed pools.

---

## Q17: "A dev team wants to deploy an architecture that violates your guidelines. What do you do?"

*(Behavioral — Anna and Melvin both likely ask this. Shows senior judgment.)*

**Headline**: "I've learned to lead with incident evidence, not principles. 'This violates best practices' gets ignored. 'This pattern caused a 2 AM page last quarter' gets attention."

**The principle I operate by:**
Don't ask teams to be more careful — build guardrails that make the wrong thing hard.

**Concrete example:**
After the Rakuten Terraform drift incident (Story 4), teams kept using console-level changes to "just fix it quickly." I could have written a policy doc. Instead I:
1. Added Terraform module input validation — `rds` module rejects CIDRs wider than `/16` for production
2. Added nightly `terraform plan` drift detection — any console change fires a Slack alert within 24 hours
3. The wrong path became harder than the right path

**For the consultative path:**
When a dev team proposes something risky, my flow:
1. **Understand first.** "Tell me what you're trying to achieve." Often the goal is valid, the approach is wrong. There's usually a safe path to the same goal.
2. **Cite evidence, not principles.** "We had a P1 from this pattern in March. Here's the RCA." Concrete > abstract.
3. **Offer the right path.** "Here's a module that does what you need, already approved, takes 20 minutes."
4. **If they still want to proceed after informed consent:** escalate to engineering lead with documented tradeoffs. I don't block — I document and escalate. The decision belongs to the org, not to me alone.
5. **If it's a security violation:** hard no. Not a discussion. "This violates PCI DSS requirement X. I'm not approving this. Let's find an alternative."

**The guardrail-first philosophy:**
> "I want teams to need me less, not more. The best outcome is that a team can't accidentally do the wrong thing — not that they have to remember to ask me."

---

## Q18: Programming Languages (Go / Rust / Python)

*(JD requires: "multiple modern programming languages, such as Go, Rust, Python")*

**What to say:**

> "Python is my primary automation language — I've written Airflow DAGs, infrastructure scripts, and data reconciliation tooling in Python. Go I've worked with for tooling and infrastructure automation — the kafka-exporter gap I ran into with MSK SASL_IAM auth is a good example: the standard Go kafka-exporter doesn't support IAM auth, so I understand why you'd reach for Go to write a custom exporter. Rust I'm learning — I understand its memory safety guarantees and why it's relevant for safety-critical systems like Woven City, but I wouldn't claim production Rust experience. I learn languages as the problem demands them."

**Don't fake Rust depth.** If asked: "Rust's ownership model eliminates memory-safety bugs at compile time — relevant for embedded or safety-critical code where a memory corruption bug could affect physical systems. That's a strong fit for Woven City's IoT device firmware layer."

---

## QUESTIONS TO ASK ANNA AND MELVIN

Pick 2-3. Do not ask about salary, WFH, or vacation.

**Q for Anna (DevOps):**
> "The JD describes Agora as an open platform for third-party inventors. How do you currently handle the trust boundary between city infrastructure services and inventor apps in production today — is it primarily network policy, service mesh, or something else?"

*(Shows you've thought about the Istio question, signals depth, gets real intel about the stack.)*

**Q for Melvin (SRE):**
> "For a city that doesn't sleep, how does the on-call rotation work in practice? Is it a follow-the-sun model with global hand-offs, or a single team with paged coverage?"

*(Shows on-call maturity, not a naive question. Tracy said on-call is office hours — this validates your understanding.)*

**Q for either:**
> "What's the hardest unsolved infrastructure problem the team is sitting on right now?"

*(Open-ended, shows genuine curiosity, gets you real signal about what you'd actually be working on day one.)*

---
