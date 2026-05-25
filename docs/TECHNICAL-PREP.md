# Agora — Deep Technical Preparation

**Interview**: May 27, 2025, 7:00 AM IST  
**Purpose**: Understand every module at resource/parameter level. Know the why behind every decision.

---

## PART 1: TERRAFORM MODULES

### Module 1: VPC (`agora-infrastructure/terraform/modules/vpc/`)

**Purpose**: Network foundation. All other modules live inside this.

**Resources created**:
| Resource | Count | Why |
|----------|-------|-----|
| `aws_vpc` | 1 | Main network boundary |
| `aws_internet_gateway` | 1 | Public subnets route to internet |
| `aws_eip` + `aws_nat_gateway` | 1 per AZ | Private subnets reach internet without being reachable |
| `aws_subnet` public | 1 per AZ | Load balancers, NAT gateways |
| `aws_subnet` private | 1 per AZ | EKS nodes, MSK brokers |
| `aws_subnet` database | 1 per AZ | Aurora instances |
| `aws_route_table` private | 1 per AZ | Each AZ routes via its own NAT (HA) |
| `aws_vpc_endpoint` S3 (Gateway) | 1 | S3 traffic stays in AWS backbone, no NAT cost |
| `aws_vpc_endpoint` Interface | 6 services | ECR, Secrets Manager, CloudWatch, AMP — no internet egress |
| `aws_flow_log` | 1 | All VPC traffic logged to CloudWatch (365 days) |

**Variables**:
| Variable | Type | Required | Notes |
|----------|------|----------|-------|
| `vpc_cidr` | string | yes | e.g. `"10.0.0.0/16"` |
| `availability_zones` | list(string) | yes | e.g. `["ap-northeast-1a","ap-northeast-1c","ap-northeast-1d"]` — length drives AZ count |
| `public_subnet_cidrs` | list(string) | yes | One per AZ |
| `private_subnet_cidrs` | list(string) | yes | One per AZ |
| `database_subnet_cidrs` | list(string) | yes | One per AZ |
| `environment` | string | yes | Used in all resource names |
| `tags` | map(string) | no | Merged into all resources |

**Key design decisions**:
- `az_count = length(var.availability_zones)` — number of AZs is a variable, not hardcoded. Pass 3 AZs → 3 NAT gateways. Pass 1 (dev) → 1 NAT, $90/mo savings.
- One private route table per AZ → if one AZ's NAT fails, only that AZ loses egress. Single route table would fail all AZs.
- VPC Gateway Endpoint for S3 — no NAT cost, no internet, faster. Required for EKS node pulling ECR images without the traffic hitting NAT.
- Interface endpoints for ECR/Secrets Manager/CloudWatch — EKS nodes can pull images and secrets with `endpoint_public_access = false` on the cluster.
- Flow logs retention 365 days — compliance. All `ACCEPT` and `REJECT` traffic recorded.

**Subnet tagging** (critical for EKS):
```hcl
"kubernetes.io/role/elb"         = "1"   # public: ALB provisioner picks these
"kubernetes.io/role/internal-elb" = "1"  # private: internal NLB picks these
"kubernetes.io/cluster/<name>"   = "shared"  # EKS knows which subnets to use
```

---

### Module 2: EKS (`agora-infrastructure/terraform/modules/eks/`)

**Purpose**: Kubernetes cluster. The compute plane for all workloads.

**Resources created**:
| Resource | Notes |
|----------|-------|
| `aws_iam_role` eks_cluster | Cluster control plane role. Attached: `AmazonEKSClusterPolicy` |
| `aws_iam_role` eks_node | Node role. Attached: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonSSMManagedInstanceCore` |
| `aws_eks_cluster` | Private endpoint only, all 5 log types enabled |
| `aws_eks_node_group` main | Initial on-demand pool. Karpenter manages the rest. |
| `aws_iam_role` karpenter_node | IAM role for Karpenter-provisioned nodes |
| `helm_release` karpenter | Karpenter v1.2.2 in kube-system |
| `aws_iam_role` ebs_csi | IRSA role for EBS CSI driver (scoped to kube-system:ebs-csi-controller-sa) |
| `aws_eks_addon` x4 | ebs-csi-driver, vpc-cni, kube-proxy, coredns |
| `aws_iam_openid_connect_provider` | OIDC provider — enables IRSA for all pods |

**Variables**:
| Variable | Default | Notes |
|----------|---------|-------|
| `cluster_name` | — | required |
| `kubernetes_version` | `"1.28"` | |
| `subnet_ids` | — | private subnet IDs from VPC module |
| `node_instance_types` | — | list, e.g. `["m5.xlarge"]` |
| `desired_size` / `min_size` / `max_size` | — | required, no defaults |
| `enable_karpenter` | `true` | set false for dev to save cost |

**Cluster config**:
```hcl
endpoint_private_access = true
endpoint_public_access  = false   # kubectl only works from inside VPC
```

**Enabled log types**: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`  
→ Full audit trail. `audit` logs capture every kubectl command.

**Node group labels**:
```hcl
labels = { "agora.io/node-pool" = "on-demand" }
```
→ Used for pod scheduling: safety-critical pods target on-demand, batch can target spot via Karpenter.

**SSM on nodes**: `AmazonSSMManagedInstanceCore` attached — no SSH bastion needed. Use Session Manager instead.

**IRSA (IAM Roles for Service Accounts)**:
- OIDC provider created from cluster issuer URL
- EBS CSI role scoped exactly to: `system:serviceaccount:kube-system:ebs-csi-controller-sa`
- Pattern: `sts:AssumeRoleWithWebIdentity` condition on exact service account name

**Karpenter** (important topic):
- Replaces Cluster Autoscaler
- Provisions nodes in response to unschedulable pods (seconds vs minutes)
- Can provision mixed instance types and spot/on-demand mix
- Karpenter IAM role has `ec2:RunInstances`, `ec2:TerminateInstances` etc.

---

### Module 3: MSK (`agora-infrastructure/terraform/modules/msk/`)

**Purpose**: Amazon Managed Streaming for Kafka. The real-time data backbone.

**Two modes** (driven by `broker_type` variable):
| Mode | Resource | When |
|------|----------|------|
| `express` | `aws_msk_cluster` | staging + production |
| `serverless` | `aws_msk_serverless_cluster` | dev (no instance to manage) |

**Express cluster resources**:
| Resource | Notes |
|----------|-------|
| `aws_security_group` | Port 9098 (IAM auth), 9096 (TLS), 2181 (ZK) — only from EKS SG |
| `aws_msk_cluster` | 3 brokers, TLS only, IAM auth only |
| `aws_msk_configuration` | `auto.create.topics.enable = false`, replication=3, compression=snappy |
| `aws_cloudwatch_log_group` | Broker logs, 30 day retention |

**Variables**:
| Variable | Default | Notes |
|----------|---------|-------|
| `broker_type` | — | `"express"` or `"serverless"` |
| `broker_node_count` | `3` | Must be multiple of AZ count |
| `instance_type` | `"express.m7g.large"` | |
| `kafka_version` | `"3.6"` | |
| `eks_cluster_security_group_id` | null | If set, SG rule uses SG ref (not CIDR) |

**Broker config** (baked into `aws_msk_configuration`):
```
auto.create.topics.enable = false   # explicit topic creation only
default.replication.factor = 3      # all topics replicate 3x
min.insync.replicas = 2             # write needs 2/3 acks
num.io.threads = 8
num.network.threads = 8
log.retention.hours = 168           # 7 days
compression.type = snappy
```

**Security**:
- `client_broker = "TLS"` — no plaintext connections
- `unauthenticated = false` — must authenticate
- `sasl { iam = true }` — IAM-only auth
- `enhanced_monitoring = "PER_TOPIC_PER_PARTITION"` — granular CloudWatch metrics

**Ports**:
- 9098 = IAM auth (SASL_SSL with MSK IAM)
- 9096 = TLS with SASL
- 2181 = ZooKeeper (Express only; serverless has no ZK)

---

### Module 4: RDS (`agora-infrastructure/terraform/modules/rds/`)

**Purpose**: Aurora PostgreSQL 15.4. Stateful storage for city services.

**Two modes**:
| Mode | `instance_class` | When |
|------|-----------------|------|
| Serverless v2 | `"db.serverless"` | dev |
| Provisioned | `"db.r6g.xlarge"` etc. | staging/prod |

**Resources created**:
| Resource | Notes |
|----------|-------|
| `random_password` | 32-char random password generated by Terraform |
| `aws_db_subnet_group` | Uses database subnets from VPC module |
| `aws_rds_cluster_parameter_group` | `rds.force_ssl=1`, `log_statement=ddl`, slow query log >1s |
| `aws_rds_cluster` | Aurora PostgreSQL, encrypted, parameter group, CloudWatch logs |
| `aws_rds_cluster_instance` writer | Performance Insights enabled, enhanced monitoring 10s |
| `aws_rds_cluster_instance` reader | `var.reader_count` replicas (0 in dev, 1+ in prod) |
| `aws_secretsmanager_secret` | Full connection string stored as JSON |
| `aws_iam_role` rds_monitoring | Enhanced monitoring role |

**Variables**:
| Variable | Default | Notes |
|----------|---------|-------|
| `instance_class` | — | `"db.serverless"` or `"db.r6g.xlarge"` |
| `serverless_min_capacity` | `0.5` | ACU (Aurora Capacity Units) |
| `serverless_max_capacity` | `2` | ACU |
| `reader_count` | `0` | Production: set to 1+ |
| `backup_retention_days` | `7` | |
| `multi_az` | `false` | true → deletion_protection on |
| `kms_key_id` | null | Pass KMS module output |

**Key configs**:
- `storage_encrypted = true` always (not a variable)
- `copy_tags_to_snapshot = true` — snapshots inherit cost tags
- `preferred_backup_window = "03:00-04:00"` — lowest traffic window (Japan time ~midnight UTC)
- `deletion_protection = var.multi_az` — if multi_az=true, can't accidentally destroy prod
- `performance_insights_retention_period = 7` — query-level perf data for 7 days free tier

**Parameter group** (important for security/compliance):
- `rds.force_ssl = 1` → TLS required, plaintext rejected
- `log_statement = ddl` → all DDL (CREATE TABLE, ALTER, DROP) logged
- `log_min_duration_statement = 1000` → queries >1s logged
- `shared_preload_libraries = pg_stat_statements` → query stats for tuning

**Credentials flow**: Terraform generates random password → stores in Secrets Manager as JSON `{username, password, host, port, dbname}` → apps use SDK to fetch, no secrets in env vars.

---

### Module 5: S3 (`agora-infrastructure/terraform/modules/s3/`)

**Purpose**: Data lake, logs, backups. Four buckets with different retention policies.

**Buckets**:
| Bucket | Purpose | Retention |
|--------|---------|-----------|
| `*-data-lake` | Kafka archives, processed/anonymized data | 7 years (2555 days) |
| `*-app-logs` | CloudTrail, VPC flow logs, ALB logs | 1 year |
| `*-access-logs` | S3 server access logs | 7 years |
| `*-backups` | Terraform state, RDS exports, DR artifacts | 3 years |

**All buckets have**:
- `block_public_acls = true`, `restrict_public_buckets = true` — no accidental public exposure
- SSE-KMS with CMK (`bucket_key_enabled = true` — reduces KMS API calls 99%)
- Bucket policy denying non-TLS access (`aws:SecureTransport = false` → Deny)
- Versioning (configurable)

**Lifecycle rules** (data lake):
```
Day 0-29:  Standard (hot, frequent access)
Day 30:    → INTELLIGENT_TIERING (auto-moves between frequent/infrequent based on access)
Day 90:    → GLACIER (cold, ML training, compliance)
Day 2555:  EXPIRE
```

**Logs bucket** (app logs):
```
Day 7:    → GLACIER (logs rarely accessed after 1 week)
Day 365:  EXPIRE
```

**Variables**:
| Variable | Default | Notes |
|----------|---------|-------|
| `bucket_prefix` | — | e.g. `"agora"` → `agora-prod-data-lake` |
| `versioning_enabled` | — | true for prod |
| `encryption_enabled` | — | true → SSE-KMS, false → AES256 (dev) |
| `kms_key_id` | — | from KMS module output |

---

### Module 6: IAM (`agora-infrastructure/terraform/modules/iam/`)

**Purpose**: IRSA roles for each Kafka consumer/producer. Least-privilege MSK topic-level permissions.

**IRSA roles created** (6 total):
| Role | MSK READ topics | MSK WRITE topics |
|------|----------------|-----------------|
| `traffic-optimizer-msk` | vehicle.telemetry, signal.events | signal.commands, incidents |
| `anomaly-detector-msk` | vehicle.telemetry | incidents, alerts.notifications |
| `energy-optimizer-msk` | sensor.environmental | alerts.notifications |
| `data-broker-msk` | vehicle.telemetry, sensor.environmental, signal.events | data.anonymized.vehicle, data.inventor.traffic |
| `kafka-connect-msk` | all topics (`*`) | — (+ S3 PutObject for sink) |
| `schema-registry-msk` | — | `_schemas` topic only |

**IRSA trust policy pattern**:
```hcl
# Each role only trusted by its exact ServiceAccount
condition {
  test     = "StringEquals"
  variable = "${oidc_provider}:sub"
  values   = ["system:serviceaccount:city-services:<service-name>"]
}
condition {
  test     = "StringEquals"
  variable = "${oidc_provider}:aud"
  values   = ["sts.amazonaws.com"]
}
```

**MSK IAM actions used**:
- `kafka-cluster:Connect` — establish connection
- `kafka-cluster:DescribeGroup` — read consumer group offsets
- `kafka-cluster:Read` + `Describe` — consume from specific topic
- `kafka-cluster:Write` + `Describe` — produce to specific topic

**Cross-account data lake** (optional):
- `aws_iam_role` `data-lake-xacct` — external account can `sts:AssumeRole` with ExternalId
- Used for data science team in separate AWS account to read S3 data

---

### Module 7: KMS (`agora-infrastructure/terraform/modules/kms/`)

**Purpose**: Customer Managed Key (CMK) for all encryption. Single key per environment.

**Resources**:
| Resource | Config |
|----------|--------|
| `aws_kms_key` | `deletion_window_in_days=30`, `enable_key_rotation=true` |
| `aws_kms_alias` | `alias/agora-<env>-cmk` |

**Key policy** grants (6 principals):
1. Account root — full `kms:*` (admin access, key never orphaned)
2. EKS node roles — `Encrypt/Decrypt/GenerateDataKey` for EBS volumes
3. S3 service principal — `GenerateDataKey/Decrypt` (with CallerAccount condition)
4. RDS service principal — full encrypt + `CreateGrant` (Aurora needs grants for cross-AZ)
5. MSK service principal — full encrypt + `CreateGrant`
6. CloudWatch Logs — encrypt/decrypt with `EncryptionContext` condition (only for this account's log groups)

**Used by**: S3 SSE-KMS, EBS volumes, RDS storage, MSK at-rest, Secrets Manager, CloudWatch Logs

---

### Module 8: Monitoring (`agora-infrastructure/terraform/modules/monitoring/`)

**Purpose**: AWS-layer monitoring. Complements in-cluster Prometheus/Grafana.

**Resources**:
| Resource | Notes |
|----------|-------|
| `aws_sns_topic` x3 | critical / warning / info — tiered alerting |
| `aws_sns_topic_subscription` | Email for critical alerts |
| `aws_prometheus_workspace` | Amazon Managed Prometheus (AMP) — optional remote write target |
| `aws_cloudwatch_dashboard` x3 | EKS, MSK, Aurora — pre-built CW dashboards |
| `aws_cloudwatch_metric_alarm` x5 | EKS node count, MSK CPU, MSK lag, Aurora CPU, Aurora replica lag |
| `aws_cloudwatch_composite_alarm` | EKS critical composite alarm → SNS critical topic |

**Alert thresholds**:
| Alarm | Threshold | Severity |
|-------|-----------|---------|
| EKS nodes | < 2 | critical |
| MSK broker CPU | > 70% | warning |
| MSK consumer lag | > 1000 | critical |
| Aurora CPU | > 70% | warning |
| Aurora replica lag | > 1000ms | warning |

---

## PART 2: KUBERNETES COMPONENTS

### Namespace Design

Three namespaces. Each is a security boundary.

```
city-services   — internal platform services (traffic-optimizer, energy-management, data-broker, api-gateway)
inventors       — external inventor workloads (sandboxed, resource-capped)
monitoring      — Prometheus, Grafana (separate to prevent accidental scrape rule changes)
```

Every namespace has `default-deny-all` NetworkPolicy applied (both Ingress and Egress denied by default).

---

### RBAC

**city-services-role** (`kustomization/base/rbac/city-services-role.yaml`):
- Full CRUD on: pods, services, configmaps, secrets, PVCs, deployments, statefulsets, HPA, NetworkPolicy, PDB
- Scoped to `city-services` namespace only (Role, not ClusterRole)

**inventors-role** (`kustomization/base/rbac/inventors-role.yaml`):
- Same resources as city-services-role
- Scoped to `inventors` namespace only
- Cannot touch `city-services` or `monitoring` at all

**What's NOT in inventors-role**:
- No access to ClusterRoles
- No ability to list nodes or namespaces
- No ability to create PriorityClasses (can't self-escalate scheduling priority)

---

### Network Policies

**default-deny-all** (`base/network-policies/default-deny-all.yaml`):
```yaml
podSelector: {}         # matches ALL pods
policyTypes: [Ingress, Egress]   # both directions blocked
# no ingress/egress rules = deny all
```
Applied to all 3 namespaces.

**inventors-allow** (`base/network-policies/inventors-allow.yaml`):
- Intra-namespace: can talk to each other freely
- Egress to `city-services/api-gateway` only (port 8080)
- Egress to internet on ports 80/443 (excluding RFC1918 — can't reach cluster internals directly)
- Cannot reach: MSK, RDS, monitoring, or other city-services pods directly

**city-services-allow** (`base/network-policies/city-services-allow.yaml`):
- Internal traffic within city-services namespace
- Ingress from api-gateway (entry point)

**monitoring-allow** (`base/network-policies/monitoring-allow.yaml`):
- Prometheus can scrape all namespaces (egress to port 8080/9090)
- Grafana can reach Prometheus

**ingress-traffic** (`base/network-policies/ingress-traffic.yaml`):
- Allows ingress controller (nginx/ALB) to reach pods

---

### Resource Quotas

**inventors-quota** (`base/resource-quotas/inventors-quota.yaml`):
```yaml
requests.cpu:    "4"     # guaranteed 4 CPU across all inventor pods
limits.cpu:      "8"     # burst up to 8 but throttled
requests.memory: "8Gi"
limits.memory:   "16Gi"
```

**city-services-quota** (`base/resource-quotas/city-services-quota.yaml`):
Higher limits (city-critical workloads get priority).

---

### Services

Each service has these manifests: `deployment.yaml`, `service.yaml`, `hpa.yaml`, `pdb.yaml`, `sa.yaml`, `servicemonitor.yaml`

**traffic-optimizer deployment key specs**:
```yaml
replicas: 2
strategy: RollingUpdate
  maxSurge: 1
  maxUnavailable: 0      # zero-downtime: always at least N pods running

priorityClassName: agora-high   # preempts lower-priority pods during resource pressure

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      topologyKey: topology.kubernetes.io/zone   # spread across AZs

resources:
  requests: { cpu: 500m, memory: 512Mi }
  limits:   { cpu: 1000m, memory: 1Gi }

securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  seccompProfile: RuntimeDefault     # syscall filtering
  capabilities: { drop: [ALL] }      # no Linux capabilities
  allowPrivilegeEscalation: false

probes:
  livenessProbe:  /health   (restart if stuck)
  readinessProbe: /ready    (remove from Service endpoints if not ready)
  startupProbe:   /startup  (30 x 5s attempts = 150s to start before liveness kicks in)
```

**HPA** (`hpa.yaml`):
```yaml
minReplicas: 2
maxReplicas: 10
metrics:
  - cpu targetUtilization: 70%
  - memory targetUtilization: 80%
behavior:
  scaleUp:   stabilizationWindowSeconds: 60   # don't thrash on spikes
             max: 2 pods per 60s OR 100%
  scaleDown: stabilizationWindowSeconds: 300  # wait 5min before scaling down
             max: 1 pod per 120s              # slow scale-down to avoid latency spikes
```

**PDB** (`pdb.yaml`):
```yaml
minAvailable: 1    # at least 1 pod must stay up during rolling updates/node drains
```

---

### Kustomize Structure

```
kustomization/
├── base/              ← single source of truth, never deployed directly
│   ├── namespaces/
│   ├── rbac/
│   ├── network-policies/
│   ├── resource-quotas/
│   ├── priority-classes/
│   ├── services/
│   │   ├── traffic-optimizer/
│   │   ├── energy-management/
│   │   ├── data-broker/
│   │   └── api-gateway/
│   └── monitoring/
└── overlays/
    ├── development/   ← reduces replicas, no anti-affinity
    │   └── patches/   reduce-traffic-optimizer.yaml, reduce-energy-management.yaml
    ├── staging/       ← moderate scale
    │   └── patches/   scale-*.yaml
    └── production/    ← full scale, strict anti-affinity
        └── patches/   scale-*.yaml, strict-anti-affinity.yaml
```

**Patch mechanism**: Strategic merge patches. Only the changed fields. Base unchanged.

Example production patch for traffic-optimizer:
```yaml
# overlays/production/patches/scale-traffic-optimizer.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traffic-optimizer
spec:
  replicas: 4   # overrides base value of 2
```

**Strict anti-affinity patch** (production only):
```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:  # HARD requirement, not preferred
      topologyKey: topology.kubernetes.io/zone
```
→ In production: scheduler will REFUSE to place 2 traffic-optimizer pods on same AZ node. In dev: preferred (won't fail if only 1 AZ available).

---

### Monitoring (In-Cluster)

**Prometheus** (full stack):
- `prometheus-deployment.yaml` — StatefulSet-like Deployment, 15d retention
- `prometheus-pvc.yaml` — 50Gi PV for metrics storage
- `prometheus-configmap.yaml` — scrape configs (auto-discovers ServiceMonitors)
- `prometheus-clusterrole.yaml` — can GET pods/endpoints/nodes across all namespaces
- `prometheus-sa.yaml` — bound to ClusterRole via ClusterRoleBinding

**Grafana**:
- `grafana-dashboards-configmap.yaml` — dashboard JSON as ConfigMap (GitOps: dashboards are code)
- `grafana-datasources-configmap.yaml` — auto-configures Prometheus as datasource on startup
- `grafana-admin-secret.yaml` — sealed admin password

**PrometheusRules** (`prometheus-rules.yaml` + pipeline `prometheus-rules-pipeline.yaml`):

K8s alerts:
| Alert | Expression | Threshold |
|-------|-----------|---------|
| TrafficOptimizerLatencyHigh | P99 of `traffic_optimizer_request_duration_seconds` | > 100ms |
| EnergyManagementErrorRateHigh | `rate(energy_management_errors_total[5m])` | > 0.001 (0.1%) |
| PodCrashLooping | `rate(kube_pod_container_status_restarts_total[5m])` | > 0.1 |
| HighMemoryUsage | container memory / limit | > 90% |

Pipeline alerts:
| Alert | Expression | Threshold |
|-------|-----------|---------|
| ConsumerLagHigh | `kafka_consumer_lag` | > 1000 messages |
| TrafficOptimizerLatencyBreach | P99 processing latency | > 100ms (SLO) |
| EnergyOptimizerLatencyBreach | P99 processing latency | > 1s |
| DeadLetterQueueAccumulating | DLQ offset delta | > 1000 |
| ProcessingErrorRateHigh | error rate per service | > 0.1% |
| KafkaConnectTaskFailed | task status = FAILED | any |
| HighThroughputWarning | bytes in/sec | > 48MB/s (80% of 60MBps cap) |
| DataBrokerHighLag | data-broker-group lag | > 5000 |
| AnomalyDetectorHighScoreRate | critical anomaly rate | > 10/min |

---

## PART 3: DATA PIPELINE

### Kafka Topics

| Topic | Partitions | Retention | Cleanup | Purpose |
|-------|-----------|---------|---------|---------|
| `vehicle.telemetry` | 12 | 7 days | delete+compact | Highest volume. 12 partitions = 12 parallel consumers. Compact keeps latest per key. |
| `sensor.environmental` | 6 | 7 days | delete | Temperature, air quality, humidity from city sensors |
| `signal.events` | 6 | 7 days | delete | Traffic signal state changes, queue lengths |
| `incidents` | 1 | 30 days | delete | **1 partition for strict ordering**. All incidents globally ordered. 30d for audit. |
| `signal.commands` | 6 | 2 days | delete | Commands to traffic lights. Short TTL — stale commands ignored. |
| `data.anonymized.vehicle` | 12 | 30 days | delete | PII-stripped vehicle data for inventors |
| `data.inventor.traffic` | 3 | 7 days | delete | Aggregated traffic data for inventor APIs |
| `alerts.notifications` | 1 | 90 days | delete+compact | Alert fan-out. 1 partition — notifications must be in order. |
| `dlq.all` | 1 | 30 days | delete | Dead letter queue. All failed messages land here. |

**All topics**: `replication_factor: 3`, `min.insync.replicas: 2`

**Why `incidents` = 1 partition?**  
Strict global ordering required. An incident acknowledged must be globally sequenced with other incidents. No need for parallelism — incidents are rare. Ordering > throughput.

**Why `vehicle.telemetry` = 12 partitions?**  
Highest throughput (most IoT devices). 12 = 12 parallel consumer threads. Partitioned by `vehicle_id` — all messages from one vehicle go to same partition (in-order per vehicle, parallel across vehicles).

---

### Avro Schemas

**vehicle.telemetry schema** (key fields):
```json
{
  "name": "VehicleTelemetry",
  "namespace": "agora.telemetry",
  "fields": [
    {"name": "vehicle_id", "type": "string"},
    {"name": "vehicle_type", "type": "enum",
     "symbols": ["autonomous","regular","emergency","public_transport","micro_mobility"]},
    {"name": "timestamp", "type": "long", "logicalType": "timestamp-millis"},
    {"name": "gps_lat/gps_lng", "type": "double"},
    {"name": "speed_kmh", "type": "float"},
    {"name": "heading_degrees/acceleration_x/y/z", "type": "float"},
    {"name": "battery_level", "type": ["null","float"], "default": null},
    {"name": "district", "type": "enum",
     "symbols": ["mobility","living","working","wellness","innovation"]},
    {"name": "event_type", "type": "enum",
     "symbols": ["periodic","emergency_brake","collision_risk","lane_departure","entering_zone","leaving_zone"]}
  ]
}
```

**Schema registry role**: Confluent Schema Registry. Stores schema versions. Producers register schema, consumers fetch by ID embedded in message. Prevents producer/consumer schema mismatch at runtime.

---

### Stream Processors

#### traffic-optimizer (`processor.py`)

**Consumer**: `vehicle.telemetry` + `signal.events`  
**Producer**: `signal.commands` + `incidents`  
**Consumer group**: `traffic-optimizer-group`

**Algorithm** (5-second tumbling window per intersection):
```
Every 5000ms per intersection_id:
  Collect: speed readings, queue lengths, emergency flags

  IF emergency vehicle detected:
    → signal.commands: "emergency_preempt" (max green = 60s)

  ELSE IF avg_queue > 50 AND avg_speed < 5 km/h:
    → signal.commands: "extend_green" (duration = queue_length * 1000ms, max 60s)

  ELSE IF avg_queue < 5 AND avg_speed > 5 km/h:
    → signal.commands: "reduce_green" (10s minimum)

Near-collision detection (within 2s window):
  IF two vehicles have speed delta > 30 km/h:
    → incidents: "near_collision", severity: "high"
```

**Producer config** (safety-critical tuning):
```python
"acks": "all"              # all ISR brokers must ack before success
"enable.idempotence": True # exactly-once semantics (no duplicate commands)
"compression.type": "snappy"
"batch.size": 65536        # 64KB batches for throughput
"linger.ms": 10            # wait 10ms to fill batch
```

**Consumer config**:
```python
"enable.auto.commit": False    # manual commit after processing
"max.poll.records": 500        # process 500 at once
"session.timeout.ms": 45000    # 45s to detect dead consumer
```

**Why manual commit?** Auto-commit can commit offsets before processing completes. If processor crashes mid-batch, messages are lost. Manual commit = process, then commit.

#### anomaly-detector (`detector.py`)

**Consumer**: `vehicle.telemetry`  
**Producer**: `incidents` + `alerts.notifications`  
**Consumer group**: `anomaly-detector-group`

**Key feature**: ML model for anomaly detection (`ANOMALY_THRESHOLD=0.8`). Loads model from `MODEL_PATH` at startup. Scores each vehicle's telemetry against historical patterns.

**Prometheus metrics**:
- `anomaly_detector_errors_total` (Counter) — error count by type
- `anomaly_detector_messages_processed_total` (Counter)
- `anomaly_detector_anomalies_detected_total` (Counter)
- Plus Histogram for processing latency

**IAM auth**: `AWS_MSK_IAM_ENABLED=true` env var switches SASL mechanism to MSK IAM. Same Avro serde pipeline as traffic-optimizer.

#### energy-optimizer (`optimizer.py`)

**Consumer**: `sensor.environmental`  
**Producer**: `alerts.notifications`  
**Logic**: Reads temperature, humidity, air quality → adjusts energy recommendations (HVAC optimization, lighting control). Emits alerts if thresholds breached.

#### data-broker (`broker.py` + transformations/)

**Consumer**: `vehicle.telemetry` + `sensor.environmental` + `signal.events`  
**Producer**: `data.anonymized.vehicle` + `data.inventor.traffic`  
**Purpose**: Sanitizes city data before it reaches the inventor-accessible topics

**Transformation pipeline** (3 steps):
1. **anonymizer.py** — strips PII fields: `{driver_id, driver_name, license_plate, payment_info, email, phone, home_address}`. Rounds GPS to 2 decimal places (~1.1km grid). Replaces vehicle_id with one-way hash.
2. **aggregator.py** — time-window aggregations: per-district vehicle counts, average speeds, congestion scores. Reduces granularity (inventor doesn't need per-vehicle data, just aggregate).
3. **access_control.py** — checks inventor subscription tier. Free tier: 5min delayed data. Premium: real-time. Enforces rate limits.

---

### Schema Registry

Confluent Schema Registry deployed as K8s service in `city-services`.

**Resources**: deployment + HPA (min 2, max 5) + PDB (min 1) + ClusterIP service  
**Topic**: `_schemas` — schema registry stores all schemas in Kafka itself (durable)  
**IAM**: `schema-registry-msk` IRSA role — read/write `_schemas` topic only

**Schema evolution rules enforced**:
- `FORWARD` compatibility: new consumers can read old messages
- Adding optional fields (with defaults): allowed
- Removing required fields: rejected
- Changing field types: rejected

---

### Kafka Connect

Runs as K8s Deployment in `city-services`. Connects Kafka → S3 (sink).

**4 connectors** (one per high-value topic):
- `s3-sink-vehicle-telemetry.json` → writes `vehicle.telemetry` to S3 data lake
- `s3-sink-environmental.json` → writes `sensor.environmental`
- `s3-sink-signal-events.json` → writes `signal.events`
- `s3-sink-incidents.json` → writes `incidents`

**S3 path pattern**: `s3://agora-prod-data-lake/kafka/<topic>/year=YYYY/month=MM/day=DD/hour=HH/`  
→ Hive-compatible partitioning. Athena can query directly without ETL.

**Format**: Avro (schema embedded via Schema Registry). Compressed: Snappy.

**Kafka Connect resources**: deployment + HPA + PDB + ClusterIP service + ConfigMap

---

### Dead Letter Queue

When any processor fails to deserialize or process a message:
1. Message written to `dlq.all` topic with error metadata
2. `dlq-processor.py` consumes from `dlq.all`
3. Attempts reprocessing with exponential backoff
4. After 3 retries: writes to S3 `dead-letter/` prefix for manual inspection

Alert: `DeadLetterQueueAccumulating` fires if DLQ offset > 1000 unprocessed.

---

## PART 4: OBSERVABILITY STACK (Phase 4)

**Project:** `agora-observability/`  
**Deploys to:** `monitoring` namespace (pre-existing from Phase 2)  
**Why Phase 4 exists:** Phase 2 deployed vanilla Prometheus + empty Grafana dashboards. ServiceMonitors and PrometheusRules from Phases 2+3 used `monitoring.coreos.com/v1` CRDs but had no Prometheus Operator → those CRDs were inert. No log aggregation, no Alertmanager, no kafka-exporter, AMP workspace existed but nothing wrote to it.

---

### Component Versions (Exact)

| Component | Image | Role |
|---|---|---|
| Prometheus Operator | `quay.io/prometheus-operator/prometheus-operator:v0.76.0` | Watches CRDs, reconciles Prometheus config |
| Prometheus | `quay.io/prometheus/prometheus:v2.51.0` | Metrics storage, rule evaluation |
| Alertmanager | `quay.io/prometheus/alertmanager:v0.27.0` | Alert routing → Slack/PagerDuty |
| Grafana | `grafana/grafana:10.4.3` | Visualization (Prometheus + Loki + AMP datasources) |
| Loki | `grafana/loki:2.9.8` | Log aggregation, S3 backend |
| Promtail | `grafana/promtail:2.9.8` | Log shipping DaemonSet |
| node-exporter | `quay.io/prometheus/node-exporter:v1.8.1` | Host-level metrics DaemonSet |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.1` | K8s object state metrics |
| kafka-exporter | `danielqsj/kafka-exporter:v1.7.0` | Consumer lag metrics |
| IAM signing proxy | `amazon/aws-signing-proxy:latest` | MSK IAM auth sidecar for kafka-exporter |

---

### Prometheus Operator — Key Design

**Why Operator matters:** Every `ServiceMonitor` and `PrometheusRule` in Phases 2+3 already uses `monitoring.coreos.com/v1` CRDs. The Operator watches those CRDs and auto-generates the Prometheus scrape config. Zero manual `prometheus-configmap.yaml` edits when adding a new service — just create a `ServiceMonitor`.

**CRDs installed** (from `crds.yaml`, 2.5MB): `prometheuses`, `alertmanagers`, `servicemonitors`, `prometheusrules`, `alertmanagerconfigs`, `podmonitors`, `probes`, `thanosrulers`

**Operator deployment args:**
```
--kubelet-service=kube-system/kubelet
--namespaces=""   (watches all namespaces — city-services, monitoring)
```

**Prometheus CRD object key config:**
```yaml
serviceMonitorSelector: {}           # matches ALL ServiceMonitors
serviceMonitorNamespaceSelector: {}  # across ALL namespaces
ruleSelector: {}                     # matches ALL PrometheusRules
replicas: 2 (base) / 1 (dev) / 2 (prod)
retention: 90d / retentionSize: 90GB
PVC: 100Gi (base), 25Gi (dev), 200Gi (prod)
```

**IRSA for AMP:** ServiceAccount `prometheus` annotated with `agora-prometheus-amp-role`. `remote_write` uses sigv4 auth to `aps-workspaces.ap-northeast-1.amazonaws.com`.

---

### Alertmanager — Routing Tree

```
Alert fires
  │
  ▼ groupBy: [alertname, severity, namespace]
  ├── severity=critical → pagerduty-critical (repeatInterval: 2h)
  ├── severity=info     → null (blackhole)
  └── default           → slack-warning, channel: #agora-alerts (repeatInterval: 4h)

groupWait: 30s  |  groupInterval: 5m
```

Credentials: `alertmanager-secret` K8s Secret holds `slack-webhook-url` + `pagerduty-routing-key`.

Alertmanager replicas: 2 (base/prod), 1 (dev). PVC: 10Gi. Uses `monitoring.coreos.com/v1alpha1 AlertmanagerConfig` CRD.

---

### Loki — Log Aggregation

**Storage model:** Index (labels + timestamps) on PVC. Log chunks compressed on S3 (`agora-{env}-app-logs/loki/`). Phase 1 created that bucket — zero new infrastructure needed.

**Config key values:**
```yaml
auth_enabled: false
schema: v12, store: tsdb (since 2024-01-01)
retention_period: 720h (30 days)
ingestion_rate_mb: 16, burst: 32
max_query_series: 500
max_entries_limit_per_query: 5000
```

**Per-env:**
| Env | Replicas | PVC |
|---|---|---|
| dev | 1 | 10Gi |
| staging | 2 | 25Gi |
| prod | 3 | 100Gi |

**IRSA:** `agora-loki-s3-role` → `s3:GetObject, s3:PutObject` scoped to `agora-{env}-app-logs/loki/*`

---

### Promtail — Log Shipping

DaemonSet on all nodes (tolerates `NoSchedule`). Reads `/var/log/pods/**/*.log` (CRI format).

**Pipeline stages:**
1. `cri: {}` — parse containerd/CRI log format
2. `json: {level, msg}` — extract structured fields
3. `labels: {level}` — promote `level` to Loki label
4. `labeldrop: [filename]` — drop high-cardinality filename label
5. `match: drop istio-proxy /healthz` — suppress health check log noise

**Labels on each log line:** `namespace`, `pod`, `container`, `service` (from `__meta_kubernetes_pod_label_app`), `level`, `node`

---

### Exporters — What Each Provides

**node-exporter** (DaemonSet, port 9100):
- `node_cpu_seconds_total` — CPU usage per mode
- `node_memory_MemAvailable_bytes` / `node_memory_MemTotal_bytes`
- `node_filesystem_avail_bytes` / `node_filesystem_size_bytes`
- `node_network_receive_bytes_total` / `node_network_transmit_bytes_total`
- `node_load1` / `node_load5` / `node_load15`
- `node_boot_time_seconds`
- hostPID: true, hostNetwork: true, mounts `/host` for rootfs access

**kube-state-metrics** (Deployment, port 8080, resources tracked: pods/deployments/replicasets/statefulsets/daemonsets/nodes/namespaces/resourcequotas/hpas/pvcs):
- `kube_pod_status_phase` — Running/Pending/Failed/Succeeded
- `kube_pod_container_status_restarts_total` — container restart count
- `kube_pod_container_status_last_terminated_reason` — OOMKilled, Error, etc.
- `kube_deployment_spec_replicas` vs `kube_deployment_status_replicas_available`
- `kube_resourcequota_used` / `kube_resourcequota_hard`
- `kube_horizontalpodautoscaler_status_current_replicas` / `spec_max_replicas`
- `kube_node_status_condition` — Ready/DiskPressure/MemoryPressure

**kafka-exporter** (Deployment, port 9308):
- `kafka_consumergroup_lag` — lag per group per partition ← feeds `ConsumerLagHigh` alert
- `kafka_consumergroup_current_offset`
- `kafka_topic_partition_current_offset`
- **MSK IAM auth limitation:** Go client doesn't support `SASL_IAM`. Workaround: `amazon/aws-signing-proxy` sidecar listens on localhost:9092, proxies to MSK broker:9098 with SigV4 signing. kafka-exporter points to localhost.

---

### Alert Rules — Complete Inventory (22 total)

**Kubernetes System Rules** (`kubernetes-system-rules.yaml`) — new in Phase 4:

| Alert | Severity | For | Condition |
|---|---|---|---|
| NodeNotReady | critical | 5m | `kube_node_status_condition{condition="Ready",status="true"} == 0` |
| PodOOMKilled | warning | 0m | `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1` |
| PodCrashLooping | critical | 5m | `rate(kube_pod_container_status_restarts_total[15m]) > 0` |
| DeploymentReplicasMismatch | warning | 10m | `kube_deployment_spec_replicas != kube_deployment_status_replicas_available` |
| ResourceQuotaNearLimit | warning | 5m | `kube_resourcequota_used / kube_resourcequota_hard > 0.85` |
| DiskPressure | warning | 5m | `node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.15` |
| NodeHighMemory | warning | 5m | `(1 - node_memory_MemAvailable / node_memory_MemTotal) > 0.90` |
| HPAMaxReplicas | warning | 10m | `hpa_status_current_replicas == hpa_spec_max_replicas` |

**App Rules** (migrated from Phase 2, `app-rules.yaml`):
TrafficOptimizerLatencyHigh (P99>100ms/5m/warning), EnergyManagementErrorRateHigh (>0.1%/5m/critical), PodCrashLooping (>0.1 restarts/s/5m/critical), HighMemoryUsage (>90% limit/5m/warning)

**Pipeline Rules** (migrated from Phase 3, `pipeline-rules.yaml`):
ConsumerLagHigh (>1000/5m/critical), TrafficOptimizerLatencyBreach, EnergyOptimizerLatencyBreach, DeadLetterQueueAccumulating, ProcessingErrorRateHigh, KafkaConnectTaskFailed, SchemaRegistryHighLatency, HighThroughputWarning (>48MB/s), DataBrokerHighLag (>5000/2m), AnomalyDetectorHighScoreRate

---

### Grafana Dashboards (4 provisioned)

Dashboards provisioned via ConfigMap (GitOps) — mounted at `/etc/grafana/dashboards`. Provider: `agora-dashboards`, type: file, updateIntervalSeconds: 10.

**Datasources:**
1. **Prometheus** — `http://prometheus-operated.monitoring.svc:9090` — default
2. **Loki** — `http://loki.monitoring.svc:3100` — maxLines: 1000
3. **AMP** — `aps-workspaces.ap-northeast-1.amazonaws.com/workspaces/...` — sigV4Auth, ec2_iam_role

**Dashboard ① Kubernetes Overview** (10 panels):
Cluster CPU/mem stat, pod count by namespace bargauge, pod phase pie, container restarts table, deployments desired vs available timeseries, node CPU heatmap, node memory heatmap, ResourceQuota usage table, HPA replica pressure timeseries

**Dashboard ② Agora Pipeline** (7 panels):
Consumer lag by group, MSK BytesIn/sec, processing latency P99 by service, DLQ accumulation stat (thresholds: green→orange@100→red@1000), error rate by processor, Kafka Connect task status table, Schema Registry request rate

**Dashboard ③ Node Exporter** (8 panels):
CPU/mem per node, disk IOPS, disk space stat (orange@10GB/red@5GB), network rx/tx, load average (1/5/15), open file descriptors, node uptime stat

**Dashboard ④ Loki Logs** (5 panels, Loki datasource):
Log volume by namespace, error rate by service, log level pie, recent errors logs panel, top error messages barchart

---

### Kustomize Overlay Patches

```
overlays/
├── development/   Loki: 1 replica/10Gi, Prometheus: 1 replica/30d/25Gi, AM: 1 replica
├── staging/       Loki: 2 replicas/25Gi (only change)
└── production/    Loki: 3 replicas/100Gi, Prometheus: 2 replicas/90d/200Gi
```

---

### Deployment

```bash
./scripts/deploy-observability.sh [development|staging|production]
```

Order matters: CRDs → Operator → exporters → Loki+Promtail → Prometheus → Alertmanager → Grafana

Verify: `./scripts/verify-stack.sh` — checks Prometheus targets, Alertmanager health, Loki /ready, Grafana datasources

Test alerting: `./scripts/test-alerts.sh` — fires TestCritical → PagerDuty, TestWarning → Slack, TestInfo → null

---

## PART 5: ARCHITECTURAL DECISIONS AND TRADE-OFFS

### Decision 1: Amazon MSK vs Self-Managed Kafka vs Kinesis

| Option | Pro | Con |
|--------|-----|-----|
| **MSK (chosen)** | Managed brokers, IAM auth, MSK Serverless for dev, deep CloudWatch integration | More expensive than self-managed; AWS-specific |
| Self-managed Kafka | Full control, cheaper at scale, multi-cloud | Ops overhead: ZooKeeper, broker upgrades, disk management |
| Kinesis | Fully serverless, auto-scaling | 7MB/s per shard limit, no consumer groups, no replay flexibility, shard resharding is disruptive |

**Why MSK**: Safety-critical system. Ops team should not be managing ZooKeeper quorums. IAM auth integrates with existing IRSA. MSK Serverless eliminates dev cost entirely. Kafka's consumer group model (independent lag per consumer) is essential for the multi-processor design.

---

### Decision 2: Single EKS Cluster vs Multi-Cluster

| Option | Pro | Con |
|--------|-----|-----|
| **Single cluster (chosen)** | Simple, consistent state, cheap, single control plane | Single blast radius, SPOF for control plane |
| Multi-cluster | Independent blast radius per cluster | Complexity: cross-cluster service discovery, inconsistent state, 2x Terraform/ops effort |

**Why single**: Woven City is one physical location. Multi-cluster provides resilience for geographic distribution, not AZ failure (EKS already handles AZ failure with nodes in 3 AZs). Control plane SLA is 99.95% (AWS-managed). If we expand to Woven City 2.0 in another city, add a second cluster then.

---

### Decision 3: Namespace Isolation vs vCluster vs Separate Clusters per Tenant

| Option | Isolation level | Cost | Ops |
|--------|----------------|------|-----|
| **Namespaces (chosen)** | Soft (RBAC + NetworkPolicy) | Free | Low |
| vCluster | Hard (virtual K8s API server per tenant) | Low (same nodes) | Medium |
| Separate EKS cluster per tenant | Physical | High (separate control plane) | Very high |

**Why namespaces**: Inventor tenant count is limited and trusted (registered inventors). Hard isolation (vCluster/separate cluster) is justified for untrusted multi-tenancy at scale (e.g., SaaS). ResourceQuota + NetworkPolicy provides sufficient containment. Can upgrade to vCluster if tenant count grows or compliance requires stronger isolation.

---

### Decision 4: Kustomize vs Helm

| Option | Pro | Con |
|--------|-----|-----|
| **Kustomize (chosen)** | Plain YAML, no templating engine, easy to audit/diff | Less powerful templating for complex conditional logic |
| Helm | Rich templating (loops, conditions), versioned charts, rollback | Template syntax obscures the actual YAML, `helm template` step required to see what's deployed |

**Why Kustomize**: The K8s manifests are the source of truth. `kubectl diff` and `git diff` work on the actual YAML. Helm charts have a compile step that can hide bugs. For our use case (env-specific scaling patches), Kustomize patches are sufficient and transparent.

---

### Decision 5: IRSA vs Node IAM Roles vs Kubernetes Secrets

| Option | Pro | Con |
|--------|-----|-----|
| **IRSA (chosen)** | Pod-level, rotates automatically, scoped to exact SA, audit trail in CloudTrail | Requires OIDC provider setup |
| Node IAM roles | Simple, no setup | All pods on node share credentials. Node compromise = all-pod compromise. No audit trail per pod. |
| K8s Secrets (manual) | Simple | Credentials stored in etcd, manual rotation, risk of secret leakage in CI/CD |

**Why IRSA**: traffic-optimizer's IAM role can only write to `signal.commands` and `incidents`. If it's compromised, attacker cannot read MSK data or touch S3. Node IAM would grant all pods on the node full access. The OIDC token auto-rotates every 15 minutes.

---

### Decision 6: Aurora Serverless v2 vs Provisioned vs DynamoDB

| Option | Pro | Con |
|--------|-----|-----|
| **Aurora Serverless v2 (dev), Provisioned (prod) (chosen)** | Dev: zero cost at idle. Prod: predictable performance. Same engine both envs. | Aurora cost higher than RDS single instance |
| RDS PostgreSQL | Cheaper, simpler | No Aurora-specific features (fast failover, global DB) |
| DynamoDB | Serverless, infinite scale | No SQL, schema migration hell, no complex queries for city service aggregations |

**Why Aurora**: Aurora failover is ~30s vs RDS Multi-AZ ~60-120s. Aurora Global Database path available if second region needed. `pg_stat_statements` for query analysis. Serverless v2 min 0.5 ACU = ~$0.07/hr (near-zero for dev).

---

### Decision 7: Prometheus + Grafana vs Datadog vs CloudWatch-only

| Option | Pro | Con |
|--------|-----|-----|
| **Prometheus + Grafana (chosen)** | Open source, no vendor lock-in, excellent Kafka/K8s integration, dashboards-as-code | Ops: manage storage, retention, HA |
| Datadog | Fully managed, great UX | ~$23/host/month at scale = significant cost for city-scale infrastructure |
| CloudWatch-only | Native AWS, zero ops | Limited cardinality, no Kafka consumer lag natively, querying is expensive |

**Why Prometheus**: At city scale (hundreds of services), Datadog cost becomes significant budget item. Prometheus is de-facto K8s standard. Grafana dashboard JSON in ConfigMap = GitOps. Prometheus rules are K8s CRDs = reviewed in PRs.

---

### Decision 11: Prometheus Operator vs Vanilla Prometheus

| Option | Pro | Con |
|--------|-----|-----|
| **Prometheus Operator (chosen)** | CRD-driven config — ServiceMonitors auto-discovered, PrometheusRules evaluated without manual configmap edits | Extra moving part: Operator deployment, CRDs to install |
| Vanilla Prometheus | Simpler, no Operator required | Manual scrape config editing for every new service, PrometheusRule CRDs inert |

**Why Operator:** Phases 2+3 already wrote `monitoring.coreos.com/v1` ServiceMonitors and PrometheusRules. The Operator makes those objects functional. As new services add ServiceMonitors, Prometheus auto-discovers them — zero config drift. The Operator also manages Prometheus and Alertmanager as StatefulSets, handles rolling upgrades, and supports sharding.

---

### Decision 12: Loki vs Elasticsearch for Log Aggregation

| Option | Pro | Con |
|--------|-----|-----|
| **Loki (chosen)** | Same label model as Prometheus, S3 storage (cheap, durable), no schema design, native Grafana integration | Limited full-text search capabilities vs Elasticsearch |
| Elasticsearch | Rich full-text search, mature tooling | Ops-heavy cluster management, 5–10x higher storage cost, separate schema per index |

**Why Loki:** 60K events/sec generates significant log volume. Loki stores only metadata + compressed chunks on S3 (using Phase 1 `agora-{env}-app-logs` bucket — no new infrastructure). Labels match Prometheus (namespace/pod/service) → Grafana Explore lets you jump from a metric spike to the logs for that exact pod in the same time window. Elasticsearch would require a dedicated cluster, schema migrations, and order-of-magnitude more storage cost.

---

### Decision 13: kafka-exporter IAM Auth Strategy

**Problem:** `danielqsj/kafka-exporter` is written in Go. MSK IAM auth (`SASL_IAM`) requires the AWS SDK and SigV4 request signing — not available in the Go Kafka client used by kafka-exporter.

**Solution:** `amazon/aws-signing-proxy` sidecar container. It listens on localhost:9092, accepts standard Kafka connections, and proxies them to MSK broker:9098 with SigV4 signatures attached. kafka-exporter points to localhost and never knows about IAM auth.

**Production alternative:** Use MSK CloudWatch metrics for broker-level consumer lag (already wired in Phase 1 `MaxOffsetLag` alarm). The proxy approach covers dev/staging; CloudWatch covers MSK in production as a fallback.

---

### Decision 8: Terraform Modules vs Terragrunt vs CDK

| Option | Pro | Con |
|--------|-----|-----|
| **Terraform modules (chosen)** | Standard, readable, broad community | Verbose env configs, no DRY across environments natively |
| Terragrunt | DRY env configs via `terragrunt.hcl` | Another abstraction layer, harder to onboard new engineers |
| AWS CDK | Type-safe, IDE support | Python/TypeScript required, harder to audit vs HCL |

**Why modules**: Infra teams are diverse. Terraform HCL is readable by ops engineers who don't write Python. Terragrunt is valuable at 10+ environments; at 3 (dev/staging/prod), Terraform native modules are sufficient. S3 + DynamoDB state management is standard and understood.

---

### Decision 9: Manual Kafka Commit vs Auto-Commit

**Chosen**: `enable.auto.commit: false` for all processors.

**Why**: Auto-commit fires on an interval (default 5000ms). If a processor receives 100 messages, auto-commits offset 100, then crashes during processing of message 50 — messages 50-100 are lost. Manual commit = call `consumer.commit()` only after all messages in the batch are processed and produced downstream. Combined with `enable.idempotence: True` on producer = exactly-once semantics.

---

### Decision 10: PII Anonymization Strategy

**Approach**: Strip at source, never expose in inventor-accessible topics.

| Field | Treatment |
|-------|-----------|
| `driver_id`, `license_plate`, `vehicle_uuid` | Deleted completely |
| `payment_info`, `credit_card` | Deleted completely |
| `gps_lat`, `gps_lng` | Rounded to 2 decimal places (~1.1km grid) |
| `speed_kmh` | Bucketed: `"50-60"` string, not exact float |
| `vehicle_id` | Replaced with deterministic hash (same vehicle = same hash, but not reversible) |

**Why round GPS to 2 decimal places?** 1 decimal = 11km precision (too coarse). 3 decimal = 111m precision (too precise for privacy). 2 decimal = 1.1km is city-district granularity. Inventors can analyze traffic patterns per district, not track individuals.

**Data flow**: `vehicle.telemetry` (raw PII) → `data-broker` (anonymizer → aggregator → access_control) → `data.anonymized.vehicle` (inventors read this). PII never leaves city-services namespace.

---

## PART 6: NUMBERS TO MEMORIZE

| Metric | Value |
|--------|-------|
| Target throughput | 60,000 events/sec |
| IoT devices | 10,000+ |
| traffic-optimizer SLO | P99 < 100ms |
| energy-optimizer SLO | P99 < 1s |
| error rate SLO | < 0.1% per service |
| vehicle.telemetry partitions | 12 |
| all topic replication factor | 3 |
| min.insync.replicas | 2 |
| Kafka retention | 7 days (default), 30 days (incidents), 2 days (commands) |
| HPA min replicas (all services) | 2 |
| HPA max replicas | 10 |
| inventors CPU quota | 4 CPU req / 8 CPU limit |
| inventors memory quota | 8Gi req / 16Gi limit |
| EKS K8s version | 1.28 |
| Kafka version | 3.6 |
| Aurora version | PostgreSQL 15.4 |
| RDS backup window | 03:00-04:00 UTC+9 |
| KMS key rotation | annual (automatic) |
| KMS deletion window | 30 days |
| S3 data lake retention | 7 years |
| VPC flow log retention | 1 year |
| Region | ap-northeast-1 (Tokyo) |
| Total infra code | 8,263 lines |
| **Phase 4 — Observability** | |
| Prometheus retention (base/prod) | 90d / 90GB |
| Prometheus retention (dev) | 30d / 20GB |
| Prometheus PVC (base/dev/prod) | 100Gi / 25Gi / 200Gi |
| Loki retention | 30 days (720h) |
| Loki PVC (dev/staging/prod) | 10Gi / 25Gi / 100Gi |
| Loki replicas (dev/staging/prod) | 1 / 2 / 3 |
| Alertmanager replicas (base/dev) | 2 / 1 |
| Alertmanager groupWait / groupInterval | 30s / 5m |
| Alertmanager repeatInterval | 4h (warning), 2h (critical) |
| Total alert rules | 22 (8 new K8s + 4 Phase 2 + 10 Phase 3) |
| Grafana dashboards | 4 (K8s Overview, Pipeline, Node Exporter, Loki Logs) |
| Prometheus Operator version | v0.76.0 |
| CRDs installed | 8 (prometheuses, alertmanagers, servicemonitors, prometheusrules, alertmanagerconfigs, podmonitors, probes, thanosrulers) |
| kafka-exporter MSK auth | aws-signing-proxy sidecar → localhost:9092 → MSK:9098 |
| Loki S3 bucket | agora-{env}-app-logs/loki/ (Phase 1 bucket, no new infra) |
| AMP remote_write auth | sigv4, IRSA role agora-prometheus-amp-role |

---

## PART 7: RECENT ADDITIONS — Istio, Terraform State Lock, DR

### What Was Recently Added and Why

Three capability areas were added to strengthen security, operational safety, and disaster readiness:

| Area | Why | Key Files |
|------|-----|-----------|
| Istio Service Mesh | Zero-trust networking: mTLS between all pods, JWT auth at mesh edge, deny-by-default authorization, defense-in-depth over NetworkPolicy | `agora-kubernetes-components/kustomization/base/istio/` |
| Terraform State Lock | Prevent concurrent state modifications, detect stale locks, automate state backups, force-unlock safety procedure | `agora-infrastructure/terraform/bootstrap/main.tf` |
| DR Alerting & Automation | DR-specific SNS topic, CloudWatch dashboard, Grafana DR dashboard, Prometheus alert rules, automated state backup CronJob, DR test scenarios | `agora-observability/kustomization/base/alert-rules/dr-rules.yaml`, `agora-infrastructure/terraform/modules/monitoring/main.tf`, `agora-kubernetes-components/kustomization/base/dr/` |

### Key Talking Points

#### Istio Service Mesh

- Two-namespace model: both `city-services` and `inventors` enforce STRICT mTLS PeerAuthentication
- AuthorizationPolicy uses deny-by-default with per-service allow rules (traffic-optimizer, data-broker, api-gateway)
- Sidecar resource restricts inventor pods to egress only to api-gateway — no direct access to MSK, Aurora, or other services
- RequestAuthentication validates JWT tokens at the Envoy proxy before the application sees the request
- MeshConfig REGISTRY_ONLY prevents outbound traffic to unknown destinations
- Adds a third security layer on top of VPC Security Groups and Kubernetes NetworkPolicy
- Telemetry enables 100% Zipkin tracing and JSON access logging
- DR rules include `IstioMTLSFailureRate` alert (> 1% failure rate triggers warning)

#### Terraform State Lock

- DynamoDB table `terraform-lock` with PAY_PER_REQUEST, PITR, streams, TTL
- S3 state bucket with versioning, 90-day noncurrent version expiration
- CloudWatch alarm on `ConditionalCheckFailedRequests` for stale lock detection
- IAM deny policy prevents non-admin force-unlock (`dynamodb:DeleteItem`)
- Force-unlock procedure documented in `prep/woven-technical-prep/02-terraform-blast-radius/force-unlock-procedure.md`
- **Critical rule**: always verify state serial before force-unlocking — if serial advanced, don't unlock
- Lock timeout patterns: 60s for CI/CD, 5m for interactive, 10m for large state

#### DR Automation

- DR SNS topic (`agora-{env}-dr`) for state lock and backup alerts
- DR CloudWatch dashboard with backup age, stale locks, lock contention widgets
- Grafana DR readiness dashboard (state backup age, mTLS failure rate, consumer lag, pod recovery time, AZ node count)
- 8 DR Prometheus alert rules in `dr-rules.yaml` (SafetyCriticalComponentDegraded, PotentialAZFailure, TerraformStaleLock, StateBackupStale, RTOBreachRisk, KafkaBrokerCountLow, IstioMTLSFailureRate, CityOperationalSLOTracking)
- Automated state backup CronJob runs nightly at 02:00 JST, copies all env states to backups bucket
- DR test scenarios: aurora-failover, kafka-broker, az-outage, terraform-state, full-drill
- Cross-region DR target region: `ap-southeast-1` (prepared but not active)

### Where to Find the Code

| Resource | Location |
|----------|----------|
| Istio K8s manifests | `agora-kubernetes-components/kustomization/base/istio/` |
| DR K8s manifests | `agora-kubernetes-components/kustomization/base/dr/` |
| Terraform bootstrap (lock table) | `agora-infrastructure/terraform/bootstrap/main.tf` |
| DR monitoring resources | `agora-infrastructure/terraform/modules/monitoring/main.tf` |
| DR Prometheus alert rules | `agora-observability/kustomization/base/alert-rules/dr-rules.yaml` |
| Force-unlock procedure | `prep/woven-technical-prep/02-terraform-blast-radius/force-unlock-procedure.md` |
| DR test failover script | `prep/woven-technical-prep/03-sre-incident-cuj-dr/dr-test-failover.sh` |
| Architecture docs | `docs/ARCHITECTURE.md` §12 (Istio), §11.1 (State Lock) |
| Operations docs | `docs/OPERATIONS.md` §8 (Lock Mgmt), §9 (Istio Ops), §10 (DR Ops) |
| DR docs | `docs/DISASTER-RECOVERY.md` §11 (Alerting & Monitoring), §3.4 (State Backups) |
