# Security Architecture — Agora Platform

> **Security architecture, threat model, IAM policies, network isolation, data protection, and compliance for the Woven City Agora smart city platform**
> **Last Updated**: May 2026

---

## Table of Contents

1. [Security Principles](#1-security-principles)
2. [Threat Model](#2-threat-model)
3. [IAM Architecture](#3-iam-architecture)
4. [Per-Service IAM Policies and IRSA](#4-per-service-iam-policies-and-irsa)
5. [Network Security](#5-network-security)
6. [Pod Security](#6-pod-security)
7. [Data Protection and PII Anonymization](#7-data-protection-and-pii-anonymization)
8. [Encryption at Rest and in Transit](#8-encryption-at-rest-and-in-transit)
9. [Secrets Management](#9-secrets-management)
10. [Compliance for Smart City Data](#10-compliance-for-smart-city-data)
11. [Audit and Incident Response](#11-audit-and-incident-response)

---

## 1. Security Principles

### Design tenets

1. **Defense in depth**: Network, IAM, encryption, K8s RBAC, network policies — no single point of failure
2. **Least privilege**: Every service, pod, and user gets only the permissions required to function
3. **Default deny**: All traffic denied by default; explicit allow rules for every communication path
4. **Encrypt everything**: Data encrypted at rest (KMS) and in transit (TLS) at all layers
5. **Zero-trust networking**: No implicit trust between services — authenticate and authorize every request
6. **Secrets-free Kafka**: IAM auth via IRSA — no passwords, no certificates, no rotation
7. **Audit everything**: All API calls, data access, and configuration changes logged and monitored

### Security requirements mapping

| Requirement | Implementation | Standard |
|-------------|---------------|----------|
| Encryption at rest | KMS CMK per environment (MSK, Aurora, S3, EBS) | AES-256 |
| Encryption in transit | TLS 1.2+ (MSK, Aurora, ALB), TLS 1.3 (S3) | NIST |
| IAM least privilege | IRSA roles per service, scoped IAM policies | AWS Well-Architected |
| Network isolation | VPC + subnets + security groups + K8s network policies | NIST 800-53 |
| Secrets management | AWS Secrets Manager with auto-rotation | SOC 2 |
| Audit logging | CloudTrail + VPC Flow Logs + S3 Access Logs | SOC 2, PCI DSS |
| Data privacy | PII stripping, GPS rounding, per-inventor ACLs | Japan APPI |

---

## 2. Threat Model

### Threat matrix

| Threat | Impact | Likelihood | Mitigation |
|--------|--------|-----------|------------|
| **Unauthorized Kafka access** | Data exfiltration, message injection | Low | IAM Access Control + IRSA + Network Policies |
| **Compromised container** | Pod-level access to topics | Low | Read-only root FS, drop all capabilities, seccomp |
| **K8s API server exposure** | Cluster compromise | Very low | EKS private endpoint (no public access), IP allowlist |
| **S3 bucket misconfiguration** | Data leak | Low | Block Public Access, bucket policies, Terraform compliance checks |
| **Aurora SQL injection** | Data exfiltration, deletion | Low | Parameterized queries, WAF on API gateway |
| **DoS from inventor** | Resource exhaustion | Medium | Resource quotas, rate limiting, HPA |
| **Supply chain (container)** | Malicious code in processor image | Low | Image scanning (Trivy), signed images, private ECR |
| **AWS credential leak** | Full AWS access | Very low | Temporary credentials (IRSA), no static keys in pods |
| **Insider threat** | Data exfiltration | Low | Audit logging, least privilege, separation of duties |
| **Cross-tenant data access** | Inventor sees city-service data | Low | Network policies, RBAC, data broker anonymization |

### Trust boundaries

```
[Internet] ── TLS ──→ [ALB] ── TLS ──→ [API Gateway Pod]
                                             │
                                        [city-services namespace]
                                             │
                                      [K8s Network Policy]
                                             │
                                        [MSK IAM Auth]
                                             │
                                        [Kafka Topics]
                                             │
                                   [Data Broker] ← anonymization boundary
                                             │
                                    [inventors namespace]
                                             │
                                    [External Inventors]
```

---

## 3. IAM Architecture

### IAM model overview

```
[AWS Account]
    │
    ├── [Human Users] ─── AWS IAM Users / SSO
    │   ├── Administrators: full access
    │   ├── Engineers: read-write (non-prod), read-only (prod)
    │   └── Auditors: read-only (all environments)
    │
    ├── [Service Roles] ─── AWS-managed
    │   ├── EKS Cluster Role
    │   ├── EKS Node Role
    │   └── Karpenter Node Role
    │
    └── [IRSA Roles] ─── Per-service, least privilege
        ├── TrafficOptimizerMSKRole
        ├── AnomalyDetectorMSKRole
        ├── EnergyOptimizerMSKRole
        ├── DataBrokerMSKRole
        ├── KafkaConnectMSKRole
        ├── SchemaRegistryMSKRole
        ├── DLQProcessorMSKRole
        └── ALBIngressControllerRole
```

### Human IAM policies

| Role | Permissions | MFA | Access Type |
|------|-------------|-----|-------------|
| Administrator | `AdministratorAccess` | Required | Console + CLI |
| Platform Engineer | Read-write on non-prod, read-only on prod | Required | CLI (assume role) |
| Security Auditor | Read-only (all services, CloudTrail) | Required | Console |
| Developer | Read-only (limited), write to dev only | Optional | CLI (assume role) |
| On-call | Read-write (all, with break-glass procedure) | Required | CLI (elevation required) |

### IRSA (IAM Roles for Service Accounts)

```
┌─────────────────────────────────────────────┐
│               EKS Cluster                    │
│                                              │
│  ┌──────────────────────────────────────┐   │
│  │  city-services namespace             │   │
│  │                                      │   │
│  │  ┌───────────────────┐               │   │
│  │  │ ServiceAccount:   │               │   │
│  │  │ traffic-optimizer │               │   │
│  │  │ annotations:      │               │   │
│  │  │  eks.amazonaws.com/│              │   │
│  │  │  role-arn: arn:...│              │   │
│  │  └────────┬──────────┘               │   │
│  │           │                          │   │
│  │           ▼                          │   │
│  │  ┌───────────────────┐               │   │
│  │  │ Pod assumes IAM   │────────────── │   │
│  │  │ role via OIDC     │  MSK IAM Auth │   │
│  │  └───────────────────┘  (port 9098)  │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
         │
         ▼
AWS IAM ───────────────────── OIDC Provider
(Trust Policy: OIDC issuer + subject)
```

### OIDC configuration

```hcl
# Terraform creates OIDC provider automatically
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = module.eks.cluster_oidc_issuer_url
}
```

### IRSA trust policy example

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E:sub": "system:serviceaccount:city-services:traffic-optimizer",
        "oidc.eks.ap-northeast-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B716D3041E:aud": "sts.amazonaws.com"
      }
    }
  }]
}
```

### Why IAM over mTLS

| Factor | mTLS | IAM Access Control |
|--------|------|-------------------|
| Certificate rotation | Manual, operational burden | None (IAM handles auth) |
| Secret management | Store certs in Secrets → mount in pods | No secrets needed |
| Pod-level auth | Complex (per-pod certs) | Native via IRSA |
| Audit trail | Application-level | CloudTrail (all API calls logged) |
| AWS integration | Manual | Native (AWS SDK) |
| Port | 9094 (TLS) | 9098 (IAM) |

---

## 4. Per-Service IAM Policies and IRSA

### Kafka permissions model

```
IAM Role → Policy → Kafka Actions → Topics/Groups
```

### The 7 IRSA roles

Every service that communicates with Kafka has its own IAM role with least-privilege permissions. Roles are scoped to exactly the topics and actions each service needs.

#### Traffic Optimizer

**Service account:** `traffic-optimizer-sa`

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeGroup"
    ],
    "Resource": [
      "arn:aws:kafka:ap-northeast-1:ACCOUNT:cluster/agora-production/*"
    ]
  }, {
    "Effect": "Allow",
    "Action": [
      "kafka-cluster:Read",
      "kafka-cluster:Describe"
    ],
    "Resource": [
      "arn:aws:kafka:ap-northeast-1:ACCOUNT:topic/agora-production/vehicle.telemetry",
      "arn:aws:kafka:ap-northeast-1:ACCOUNT:topic/agora-production/signal.events"
    ]
  }, {
    "Effect": "Allow",
    "Action": [
      "kafka-cluster:Write",
      "kafka-cluster:Describe"
    ],
    "Resource": [
      "arn:aws:kafka:ap-northeast-1:ACCOUNT:topic/agora-production/signal.commands",
      "arn:aws:kafka:ap-northeast-1:ACCOUNT:topic/agora-production/incidents"
    ]
  }]
}
```

| Action | Resource | Rationale |
|--------|----------|-----------|
| Connect | Cluster | Required for any Kafka interaction |
| DescribeGroup | Group `traffic-optimizer-group` | Monitor own consumer lag |
| Read | `vehicle.telemetry`, `signal.events` | Process traffic data and signal events |
| Write | `signal.commands`, `incidents` | Output optimization commands and incident reports |

#### Anomaly Detector

**Service account:** `anomaly-detector-sa`

| Action | Resource | Rationale |
|--------|----------|-----------|
| Connect | Cluster | Required for Kafka interaction |
| Read | `vehicle.telemetry` | Analyze vehicle telemetry for anomalies |
| Write | `incidents`, `alerts.notifications` | Report detected anomalies |

#### Energy Optimizer

**Service account:** `energy-optimizer-sa`

| Action | Resource | Rationale |
|--------|----------|-----------|
| Connect | Cluster | Required for Kafka interaction |
| Read | `sensor.environmental` | Process environmental sensor data |
| Write | `alerts.notifications` | Report optimization events |

#### Data Broker

**Service account:** `data-broker-sa`

| Action | Resource | Rationale |
|--------|----------|-----------|
| Connect | Cluster | Required for Kafka interaction |
| Read | `vehicle.telemetry`, `sensor.environmental`, `signal.events` | Read all raw data for anonymization |
| Write | `data.anonymized.vehicle`, `data.inventor.traffic` | Write anonymized output |
| Write (S3) | `agora-prod-data-lake` | Archive processed data |

This is the most privileged Kafka role — it reads all raw topics. The data broker is the single service trusted to handle raw PII data before anonymization.

#### Kafka Connect

**Service account:** `kafka-connect-sa`

| Action | Resource | Rationale |
|--------|----------|-----------|
| Connect | Cluster | Required for Kafka interaction |
| Read | All raw topics (`vehicle.telemetry`, `sensor.environmental`, `signal.events`, `incidents`) | Archive all data to S3 |
| Write (S3) | `agora-prod-data-lake` | S3 sink connector output |

#### Schema Registry

**Service account:** `schema-registry-sa`

| Action | Resource | Rationale |
|--------|----------|-----------|
| Connect | Cluster | Required for Kafka interaction |
| Read | `_schemas` topic | Read schema registry internal topic |
| Write | `_schemas` topic | Register new schema versions |

#### DLQ Processor

**Service account:** `dlq-processor-sa`

| Action | Resource | Rationale |
|--------|----------|-----------|
| Connect | Cluster | Required for Kafka interaction |
| Read | `dlq.all` | Read failed messages for classification |
| Write | `alerts.notifications` | Alert on DLQ accumulation |

### Service account annotations

Apply IRSA annotations to each service account:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: traffic-optimizer-sa
  namespace: city-services
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/TrafficOptimizerMSKRole
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: anomaly-detector-sa
  namespace: city-services
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/AnomalyDetectorMSKRole
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: energy-optimizer-sa
  namespace: city-services
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/EnergyOptimizerMSKRole
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: data-broker-sa
  namespace: city-services
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/DataBrokerMSKRole
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-connect-sa
  namespace: city-services
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/KafkaConnectMSKRole
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: schema-registry-sa
  namespace: city-services
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/SchemaRegistryMSKRole
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dlq-processor-sa
  namespace: city-services
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/DLQProcessorMSKRole
```

### Kafka client configuration (IAM auth)

```properties
# No username/password — IAM auth only
bootstrap.servers=b-1:9098,b-2:9098,b-3:9098

# AWS SDK credentials provider (IRSA)
sasl.mechanism=AWS_MSK_IAM
security.protocol=SASL_SSL
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler

# No TLS cert config needed (IAM uses AWS TLS certs)
```

---

## 5. Network Security

### VPC architecture

| Layer | Access | Rationale |
|-------|--------|-----------|
| Public subnets | NAT Gateways, ALB only | No compute resources in public subnets |
| Private subnets | EKS nodes, MSK, stream processors | No direct internet access |
| Database subnets | Aurora PostgreSQL only | Most restricted, no internet at all |

### Security groups

| Security Group | Inbound Rules | Outbound Rules |
|---------------|---------------|----------------|
| EKS cluster | EKS control plane (443), Karpenter (10250) | All VPC traffic |
| EKS nodes | Nodes within sg (all ports), ALB (8080), monitoring (9090) | All VPC traffic, ECR, S3, Secrets Manager |
| MSK | EKS node SG (9098 IAM, 9096 TLS) | None (within VPC) |
| Aurora | EKS node SG (5432) | None (within VPC) |
| ALB | Internet (443), health checks | EKS node SG (8080) |

### VPC endpoints

All AWS API calls stay within the AWS network:

| Endpoint Type | Service | Purpose |
|--------------|---------|---------|
| Gateway | S3 | Object storage access |
| Interface | ECR API | Container registry API |
| Interface | ECR DKR | Docker image pulls |
| Interface | Secrets Manager | DB credential retrieval |
| Interface | CloudWatch | Metric and log delivery |
| Interface | CloudWatch Logs | Log group access |
| Interface | AMP | Prometheus workspace |

### Kubernetes network policies

Three layers of network isolation applied to every namespace:

#### Layer 1: Default deny all

Applied to every namespace as a baseline. No ingress or egress allowed by default.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: city-services
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

#### Layer 2: Per-namespace allow rules

**city-services namespace:**

```
Ingress:
  └─ from: monitoring namespace → port 8080 (Prometheus metrics)
  └─ from: city-services pods → port 8080 (intra-service)
Egress:
  └─ to: kube-system → UDP 53 (DNS)
  └─ to: VPC CIDR → TCP 9098 (MSK IAM auth)
  └─ to: city-services pods → TCP 8080 (intra-service)
```

**inventors namespace:**

```
Ingress:
  └─ from: api-gateway.city-services → port 8080 (API access only)
Egress:
  └─ to: kube-system → UDP 53 (DNS only)
```

#### Layer 3: Cross-namespace exceptions

Only explicitly allowed cross-namespace traffic:

- `inventors` → `api-gateway` (port 8080) in `city-services`
- `city-services` → `prometheus` (port 9090) in `monitoring`
- `monitoring` → all namespaces (metrics scraping on port 8080)

### Network policy for city-services

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: city-services-allow
  namespace: city-services
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
      ports:
        - protocol: TCP
          port: 8080
    - from:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
    - to:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 8080
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8  # VPC CIDR (MSK in private subnets)
      ports:
        - protocol: TCP
          port: 9098           # IAM auth port
```

### DDoS protection

| Layer | Protection |
|-------|-----------|
| Network | AWS Shield Standard (automatic) |
| Application | WAF on ALB (rate limiting, SQL injection, XSS) |
| API Gateway | Per-API-key rate limiting |
| Application | Connection pooling, request timeouts |

---

## 6. Pod Security

### Pod security context

Applied to every pod in `city-services` and `inventors` namespaces:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001           # Non-root user
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault     # Restrict syscalls

containers:
  - securityContext:
      readOnlyRootFilesystem: true     # Prevent container escape via FS write
      allowPrivilegeEscalation: false  # No privilege escalation
      capabilities:
        drop:
          - ALL                        # Drop all Linux capabilities
```

### Pod security standards (PSS)

| Namespace | Policy | Enforcement |
|-----------|--------|-------------|
| city-services | Restricted | `enforce` (reject violations) |
| inventors | Restricted | `enforce` (reject violations) |
| monitoring | Baseline | `warn` (allow Prometheus host networking) |
| kube-system | Privileged | `audit` (system components need privileges) |

### Admission controllers

| Controller | Purpose |
|------------|---------|
| PodSecurity | Enforce PSS (Restricted for user namespaces) |
| NodeRestriction | Limit kubelet self-modification |
| AlwaysPullImages | Ensure fresh images, no local cache poisoning |
| DefaultStorageClass | Ensure PVCs use encrypted EBS |

### Image security

```yaml
# All images pulled from private ECR (no public registries)
imagePullPolicy: Always

# Image signed and scanned before push
# Trivy scan as CI step
# Only images with PASSED scan allowed to deploy
```

---

## 7. Data Protection and PII Anonymization

### Data classification

| Class | Definition | Examples | Storage |
|-------|-----------|----------|---------|
| Public | No sensitivity | Aggregated city statistics, weather data | S3 (unencrypted or SSE-S3) |
| Internal | Internal operations | Microservice configs, deployment logs | S3 SSE-KMS, CloudWatch |
| Confidential | Business-sensitive | Device telemetry, traffic patterns, building energy | MSK KMS, Aurora KMS, S3 SSE-KMS |
| Restricted | PII, personal data | Vehicle IDs, driver identity, home locations | Aurora KMS (encrypted columns), never in Kafka raw beyond retention |

### PII anonymization pipeline

The data-broker stream processor is the single service trusted to handle raw PII data. It applies a three-stage anonymization pipeline before data reaches any consumer (city-services or inventors).

#### Stage 1: Anonymizer — Strip PII fields

**Vehicle telemetry anonymization:**

```
Raw message from vehicle.telemetry:
{
  "vehicle_id": "V-12345",
  "vehicle_type": "sedan",
  "driver_id": "D-98765",
  "lat": 35.123456,
  "lng": 140.456789,
  "speed": 45,
  "heading": 180,
  "timestamp": "2026-05-16T14:32:45.123Z",
  "vin": "JT2BF22KXX0123456",
  "payment_info": "card-XXXX-1111"
}

  ↓ Anonymizer applies these transformations:

  Remove entirely:   vehicle_id, driver_id, vin, payment_info
  Round to 100m:     lat → 35.12, lng → 140.46
  Round timestamp:   "14:32:45.123Z" → "14:32:00Z"
  Speed bucketing:   45 km/h → "40-60 km/h" band

Anonymized message:
{
  "vehicle_type": "sedan",
  "grid_lat": 35.12,
  "grid_lng": 140.46,
  "speed_band": "40-60",
  "heading": 180,
  "timestamp": "2026-05-16T14:32:00Z"
}
```

**Environmental sensor anonymization:**

```
Raw message from sensor.environmental:
{
  "sensor_id": "ENV-8891",
  "district": "mobility",
  "temperature": 28.5,
  "humidity": 65,
  "air_quality_index": 42,
  "building_id": "BLD-A07",
  "unit_number": "APT-301"
}

  ↓ Anonymizer:
  Remove:       sensor_id, building_id, unit_number
  Round:        temperature → 28.5 (nearest 0.5°C)
                humidity → 65 (nearest 5%)
                
Anonymized message:
{
  "district": "mobility",
  "temperature": 28.5,
  "humidity": 65,
  "air_quality_index": 42
}
```

#### Stage 2: Aggregator — Windowed aggregation per district

10-second tumbling window per district:

```
Raw window data:
  38 vehicles in Mobility district
  Speeds: [12, 45, 32, 55, 23, 41, 38, ...]
  
  ↓ Aggregator

Aggregated output:
{
  "district": "mobility",
  "time_bucket": "2026-05-16T14:32:00Z",
  "vehicle_count": 38,
  "avg_speed": 42,
  "congestion_level": "medium",
  "vehicle_breakdown": {
    "sedan": 22,
    "suv": 8,
    "autonomous": 5,
    "emergency": 1,
    "bicycle": 2
  }
}
```

#### Stage 3: Access control — Per-consumer data policies

```yaml
# access-control.yaml
inventors:
  traffic-prediction-app:
    allowed_topics:
      - data.inventor.traffic
    allowed_fields:
      - district
      - avg_speed
      - congestion_level
      - time_bucket
    denied_fields:
      - vehicle_id           # Never exposed
      - exact_coordinates    # Never exposed
    rate_limit: 1000 req/min
    quota:
      max_storage: 100GB

  energy-startup:
    allowed_topics:
      - data.anonymized.vehicle
    allowed_fields:
      - district_energy_kwh
      - avg_temperature
      - occupancy_percentage
    denied_fields:
      - unit_level_consumption    # No per-unit data
      - resident_activity         # No personal behavior data
    rate_limit: 500 req/min
```

### S3 data lake access control

| Bucket | Access | Encryption | Notes |
|--------|--------|-----------|-------|
| data-lake | EKS IRSA roles only | SSE-KMS | Console access denied via policy |
| app-logs | Security team + SRE | SSE-KMS | CloudTrail, flow logs |
| access-logs | Security team only | SSE-KMS | Audit logs, immutable (Object Lock) |
| backups | SRE + DR runbooks | SSE-KMS | Restore only, no write from prod |

### Data isolation enforcement

- **city-services**: Direct access to MSK via IRSA. Can read raw and processed topics.
- **inventors**: No direct Kafka access. Data received only through the api-gateway after anonymization.
- **Network policies**: Explicitly block inventors → Kafka traffic (port 9098 not in any inventors egress rule).
- **Data broker**: All raw data passes through the anonymization pipeline before reaching output topics.

---

## 8. Encryption at Rest and in Transit

### Encryption at rest

| Service | Key Management | Algorithm | Notes |
|---------|---------------|-----------|-------|
| MSK Kafka | KMS CMK | AES-256 | Auto-encrypts all topic data |
| Aurora PostgreSQL | KMS CMK | AES-256 | Encrypts data, logs, backups |
| S3 | SSE-KMS (same CMK) | AES-256 | Bucket policy enforces SSE-KMS |
| EBS volumes | KMS CMK (default) | AES-256 | All EKS node volumes encrypted |
| Secrets Manager | KMS CMK | AES-256 | Auto-rotating credentials |

**Key alias**: `alias/agora-{env}-cmk`

### Encryption in transit

| Path | Protocol | Port | Enforcement |
|------|----------|------|-------------|
| Device → IoT Gateway | mTLS | 443 | Device cert required |
| IoT Gateway → MSK | SASL_SSL (IAM) | 9098 | TLS 1.2+ |
| EKS Pod → MSK | SASL_SSL (IAM) | 9098 | TLS 1.2+ |
| EKS Pod → Aurora | SSL/TLS | 5432 | `rds.force_ssl=1` |
| Client → ALB | TLS | 443 | ALB listener |
| ALB → EKS Pod | TLS (internal) | 8443 | mTLS optional |
| Pod → S3 | HTTPS | 443 | Bucket policy `aws:SecureTransport` |
| EKS → ECR | HTTPS | 443 | VPC endpoint |

### KMS key policy

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "Enable IAM User Permissions",
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::ACCOUNT:root"
    },
    "Action": "kms:*",
    "Resource": "*"
  }, {
    "Sid": "Allow service-linked roles",
    "Effect": "Allow",
    "Principal": {
      "AWS": [
        "arn:aws:iam::ACCOUNT:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
      ]
    },
    "Action": [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ],
    "Resource": "*"
  }]
}
```

---

## 9. Secrets Management

### What we store in Secrets Manager

```hcl
# Aurora credentials (auto-rotated every 30 days)
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "agora-${var.environment}-db-credentials"
  description             = "Aurora PostgreSQL master credentials for Agora ${var.environment}"
  kms_key_id             = aws_kms_key.agora.arn
  rotation_rules {
    automatically_after_days = 30
  }
}

# Application API keys (e.g., external service integrations)
resource "aws_secretsmanager_secret" "api_keys" {
  name                    = "agora-${var.environment}-api-keys"
  kms_key_id             = aws_kms_key.agora.arn
}

# Grafana admin password
resource "aws_secretsmanager_secret" "grafana_admin" {
  name                    = "agora-${var.environment}-grafana-admin"
  kms_key_id             = aws_kms_key.agora.arn
}

# S3 data lake write credentials (for Kafka Connect)
resource "aws_secretsmanager_secret" "kafka_connect" {
  name                    = "agora-${var.environment}-kafka-connect"
  kms_key_id             = aws_kms_key.agora.arn
}
```

### What we DON'T store in Secrets

```
❌ Kafka username/password   → IAM auth (no secrets needed)
❌ TLS certificates           → ACM (auto-renewed) or IAM (no certs for Kafka)
❌ AWS access keys            → IRSA (temporary credentials via OIDC)
❌ Database connection strings → Constructed from Terraform outputs + Secrets Manager
```

### Pod access to secrets

```yaml
# Pod accesses Secrets Manager via IRSA, not K8s Secrets
# (K8s Secrets are base64-encoded, not encrypted at rest by default)

# K8s Secret only used for configuration data
apiVersion: v1
kind: Secret
metadata:
  name: traffic-optimizer-apikey
  namespace: city-services
type: Opaque
stringData:
  api_key: "ENCRYPTED_IN_PIPELINE"    # Encrypted in CI/CD, decrypted at deploy time
  # No Kafka credentials — IAM auth means no secrets
```

### Secrets manager IAM policy

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ],
    "Resource": [
      "arn:aws:secretsmanager:ap-northeast-1:ACCOUNT:secret:agora-${env}-*"
    ]
  }]
}
```

---

## 10. Compliance for Smart City Data

### Applicable frameworks

| Framework | Relevance | Key controls |
|-----------|-----------|-------------|
| **Japan APPI** (Act on the Protection of Personal Information) | Resident data protection in Woven City | Data anonymization, consent management, purpose limitation, cross-border transfer restrictions |
| **ISO 27001** | Information security management | Encryption, IAM, incident response, audit logging, supplier security |
| **SOC 2** (Type II) | Service organization controls | Availability (99.95%), security (encryption, IAM), confidentiality (data broker anonymization) |
| **NIST SP 800-53** | Security and privacy controls | AC (access control), AU (audit and accountability), SC (system and communications protection), SI (system and information integrity) |
| **AWS Well-Architected Framework** | Cloud security best practices | Security pillar applied to all architecture decisions |

### Japan APPI compliance for Woven City

The Agora platform processes data from residents and visitors of Woven City. Japan APPI (Act on the Protection of Personal Information) requires:

#### Personal information handling

| APPI Requirement | Agora Implementation |
|-----------------|---------------------|
| **Purpose limitation** | Data collected only for city operations (traffic optimization, energy management, safety). No secondary use without consent. |
| **Data minimization** | Data-broker anonymization pipeline strips PII before any non-essential processing. Raw data retained max 7 days. |
| **Consent management** | Device registration includes opt-in for data collection. API gateway enforces API-key based consent scope. |
| **Cross-border transfer** | All data stays in `ap-northeast-1` (Tokyo region). No transfer outside Japan. |
| **Breach notification** | CloudTrail + SNS alerts trigger incident response within required notification timeline. |
| **Retention limitation** | Kafka topics retain raw data 7 days max. S3 lifecycle policies delete after 7 years. |

#### PII identification

The following fields are classified as personal information under APPI and are stripped or anonymized by the data broker:

| Field | Classification | Handling |
|-------|---------------|----------|
| Vehicle ID (`vehicle_id`) | Personal identifier | Stripped entirely |
| Driver ID (`driver_id`) | Personal identifier | Stripped entirely |
| VIN | Personal identifier | Stripped entirely |
| GPS coordinates (<1km resolution) | Location data | Rounded to 100m grid |
| Home address | Location data | Stripped entirely |
| Payment information | Financial data | Stripped entirely |
| Building unit number | Residence identifier | Stripped entirely |

### Smart city specific considerations

| Consideration | Implementation |
|---------------|---------------|
| **District-based data segregation** | Topics partitioned by district (Mobility, Living, Working, Wellness, Innovation). District-specific access controls. |
| **Emergency override** | Emergency vehicles bypass anonymization for incident response. Anomaly detector has elevated read access. |
| **Inventor sandbox** | Inventors namespace isolated by network policies. Only anonymized, aggregated data available via API gateway. |
| **Audit for every data access** | CloudTrail + K8s audit logs capture all data access. S3 Access Logs capture every object read. |
| **Data retention zones** | Raw: 7 days (Kafka). Processed: 30 days (S3). Archived: 7 years (Glacier). |
| **Right to deletion** | Mechanism to purge individual device data from all storage tiers within 30 days. |

### Data retention by tier

| Storage Tier | Raw Data | Processed Data | Archived Data |
|-------------|----------|---------------|---------------|
| **Kafka topics** | 7 days (delete policy) | 30 days | N/A |
| **S3 data lake (raw)** | 30 days Standard → Glacier @ 90d | 30 days Standard → Glacier @ 90d | N/A |
| **S3 data lake (processed)** | N/A | 90 days Standard | 7 years Glacier |
| **S3 access logs** | 90 days Standard | 1 year Standard | 7 years Glacier |
| **Aurora** | 30 days (backup retention) | N/A | N/A |
| **CloudWatch logs** | 30 days | N/A | N/A |

---

## 11. Audit and Incident Response

### Audit logging

| Log Source | Destination | Retention | Purpose |
|-----------|-------------|-----------|---------|
| CloudTrail (management) | S3 + CloudWatch | 7 years | All AWS API calls |
| CloudTrail (data) | S3 | 7 years | S3 object-level operations |
| VPC Flow Logs | S3 + CloudWatch | 1 year | Network traffic audit |
| S3 Access Logs | S3 (access-logs bucket) | 7 years | S3 request audit |
| MSK broker logs | CloudWatch | 30 days | Kafka operations |
| Aurora logs | CloudWatch | 30 days | DB query audit, errors |
| K8s audit logs | CloudWatch | 30 days | K8s API server requests |
| Application logs | stdout → CloudWatch | 30 days | Service-level audit |

### Audit alerting

| Event | Alert | Action |
|-------|-------|--------|
| IAM policy change | Security notification | Review in 1 hour |
| Security group change | Security notification | Review in 1 hour |
| S3 bucket policy change | Security notification | Review immediately |
| KMS key deletion | Critical alert | Prevent (key deletion requires waiting period) |
| Root account activity | Critical PagerDuty | Investigate immediately |
| Console login without MFA | Warning | Disable access |
| Failed Kafka auth attempts | Warning | Investigate (possible attack) |

### Security incident response

| Scenario | Detection | Containment | Recovery |
|----------|-----------|-------------|----------|
| Compromised pod | Pod behavior anomaly, unusual network traffic | `kubectl delete pod`, isolate with network policy | Restore from known-good image, rotate any secrets |
| Compromised IAM role | CloudTrail unusual API calls | `aws iam detach-role-policy`, revoke OIDC session | Rotate credentials, audit IRSA configuration |
| Data exfiltration (S3) | S3 Access Logs show unusual download patterns | `aws s3api put-bucket-policy` to deny all, enable CloudTrail data events | Restore from versioning, rotate CMK |
| Unauthorized Kafka access | MSK CloudWatch auth failures | Update MSK IAM policies to deny | Revoke IRSA role, audit MSK ACLs |
| K8s API server compromise | CloudTrail/K8s audit logs | `eksctl delete cluster` (worst case) | Rebuild from Terraform + restore state |

### Break-glass procedure

For emergency access when normal authentication is unavailable:

```bash
# Step 1: SSO admin elevates engineer's role
aws sts assume-role \
  --role-arn "arn:aws:iam::ACCOUNT:role/BreakGlassRole" \
  --role-session-name "break-glass-$(date +%s)" \
  --duration-seconds 3600

# Step 2: All break-glass actions logged to CloudTrail
# Step 3: Post-incident audit of all break-glass usage
# Step 4: Rotate any credentials used during break-glass
```

### Security contacts

| Role | Contact | Availability |
|------|---------|-------------|
| Security Team | security@agora.woven-city.jp | Business hours |
| Security On-Call | PagerDuty: SEC-ROTATION | 24/7 |
| CISO | ciso@woven-by-toyota.com | Business hours |
| AWS Security | AWS Support (Enterprise) | 24/7 (15 min response) |
| Japan Data Protection | dpo@woven-by-toyota.com | Business hours |
