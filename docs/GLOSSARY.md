# Glossary — Agora Platform

> **Definitions for all platform terms, technologies, and acronyms used in the Woven City Agora documentation.**
> **Last Updated**: May 2026

---

## A

### Agora
The operating system of Woven City — Toyota's smart city platform. Agora ingests and processes 60,000+ real-time events/second from 10,000+ IoT devices, providing a multi-tenant infrastructure for city management services (traffic optimization, energy management, anomaly detection) and an external inventor ecosystem. The platform is built on AWS across 3 Availability Zones in the `ap-northeast-1` region.

### Anomaly Detector
A Kafka Streams processor that reads from `vehicle.telemetry` and produces to `incidents` and `alerts.notifications`. Uses a pre-trained ML model for feature extraction and anomaly scoring. Triggers when anomaly score exceeds 0.8. Runs in the `city-services` namespace with 2–8 pods (HPA-scaled). SLO: P99 < 500ms.

### Anonymization Engine
A component of the **Data Broker** processor that strips PII (personally identifiable information) from raw telemetry data before distributing it to the multi-tenant inventor ecosystem. Operations include: removing vehicle IDs, rounding GPS coordinates to a 100m grid, removing driver identities and payment info, and hashing intersection IDs.

### Aurora (Amazon Aurora PostgreSQL)
AWS-managed relational database service compatible with PostgreSQL. Agora uses Aurora PostgreSQL 15.4 for persistent storage. Key properties: ~30s failover (vs ~120s for standard RDS), auto-scaling storage up to 128 TB, Multi-AZ with up to 2 reader replicas. Configuration varies by environment (Serverless v2 for dev, provisioned for staging/prod).

### Availability Zone (AZ)
An isolated data center within an AWS region. The Agora platform spans 3 AZs (apne1-az1, apne1-az2, apne1-az3) in `ap-northeast-1` to achieve 99.95% availability. Each AZ has its own public, private, and database subnets.

### AVRO
A compact, fast binary serialization format used for all Kafka messages in the Agora pipeline. AVRO schemas are stored in the **Schema Registry**, enabling schema evolution with compatibility guarantees. AVRO is preferred over JSON for its smaller payload size and faster serialization/deserialization.

---

## B

### Bootstrap Servers
The initial list of Kafka broker addresses that clients connect to. For Agora: `b-1:9098,b-2:9098,b-3:9098` on port 9098 (IAM auth). The bootstrap servers return metadata about the full cluster topology.

---

## C

### Canary Deployment
A deployment strategy where a new version is rolled out to a small subset of instances (the "canary") before being released to all instances. If the canary performs well (no errors, latency within SLO), the rollout continues. Agora uses this strategy for stream processor updates via Kubernetes rolling updates with `maxSurge` and `maxUnavailable` controls.

### CloudWatch (Amazon CloudWatch)
AWS monitoring and observability service. In Agora, CloudWatch is used for infrastructure-level monitoring: MSK broker metrics, Aurora database metrics, ALB metrics, EKS cluster metrics, and VPC flow logs. Terraform manages CloudWatch dashboards and composite alarms. CloudWatch is complemented by Prometheus/Grafana for application-level monitoring.

### Consumer Group
A Kafka construct that allows multiple consumer instances to coordinate reading from a topic. Each partition is assigned to exactly one consumer within a group. Agora stream processors (traffic-optimizer, anomaly-detector, etc.) each have their own consumer group. Consumer lag measures how far behind the group is from the latest message.

### Consumer Lag
The difference between the latest message offset in a Kafka topic partition and the offset that a consumer group has processed. High consumer lag (> 1000) triggers alerts and HPA scale-up actions. The lag metric is exposed through MSK CloudWatch metrics and custom Prometheus metrics from the Kafka clients.

---

## D

### Data Broker
A Kafka Streams processor that serves as the multi-tenant data gateway. Reads from raw topics (`vehicle.telemetry`, `sensor.environmental`, `signal.events`), applies **Anonymization Engine** transformations (PII stripping, GPS rounding), and writes to output topics (`data.anonymized.vehicle`, `data.inventor.traffic`). Enforces per-inventor access control rules. Runs 5–20 pods in `city-services` namespace. SLO: P99 < 200ms.

### Dead Letter Queue (DLQ)

### DR (Disaster Recovery)
The processes, policies, and infrastructure that enable restoring critical services after a catastrophic failure. Agora's DR strategy covers: multi-AZ tolerance (survive any single AZ failure), data backup (S3 archives, Aurora snapshots, Terraform state backups), automated state backup (nightly CronJob), DR alerting (dedicated SNS topic, CloudWatch dashboard, Prometheus alert rules), and defined recovery procedures with measured RTO and RPO targets. See `docs/DISASTER-RECOVERY.md` for detailed runbooks.

### DynamoDB Lock Table
A DynamoDB table (`terraform-lock`) used by Terraform to prevent concurrent state modifications. Each `terraform apply` or `plan` acquires a lock by writing an item to the table. The lock is released when the operation completes. The table has PITR enabled, KEYS_ONLY streams for monitoring, and a TTL attribute (`TimeToExist`) for automatic lock expiration. Stale locks are detected via a CloudWatch alarm on `ConditionalCheckFailedRequests`.
A Kafka topic (`dlq.all`) that captures messages that failed processing. When a stream processor encounters an error (schema violation, deserialization error, transient processing failure), it writes the original message along with error metadata to the DLQ. A dedicated DLQ processor reads from this topic, classifies failures (schema, deserialization, transient, poison pill), and takes appropriate action (retry, alert, discard).

### DLQ Processor
A dedicated consumer that reads from the `dlq.all` topic, classifies failed messages, and handles them appropriately: retries transient errors up to 3 times, alerts on schema violations and deserialization errors, and discards poison pills with an audit log entry.

---

## E

### EKS (Amazon Elastic Kubernetes Service)
AWS-managed Kubernetes service that hosts all Agora microservices. The EKS cluster runs in private subnets across 3 AZs, uses Karpenter for node auto-scaling, and integrates with AWS IAM via OIDC for IRSA. Cluster version: 1.28.

### ElastiCache (Amazon ElastiCache for Redis)
AWS-managed Redis service used by Agora for rate limiting, aggregation caching, and temporary data storage. Provides sub-millisecond latency for cache operations.

### Energy Optimizer
A Kafka Streams processor that reads from `sensor.environmental` and produces to `alerts.notifications` and `energy.commands`. Uses weather + consumption + occupancy data to shift energy from peak to off-peak periods. Runs 2–6 pods in `city-services` namespace. SLO: P99 < 1s.

---

## F

### Force-Unlock
A Terraform command (`terraform force-unlock`) that manually removes a stuck state lock from the DynamoDB table. This is a last-resort operation. The safe procedure requires: verifying the lock exists, checking the state serial has not advanced (which would indicate a partially successful apply), confirming the lock holder is offline, and only then removing the lock. Agora enforces an IAM deny policy that restricts `dynamodb:DeleteItem` on the lock table to admin roles only. See `docs/DISASTER-RECOVERY.md` §9.2 for the full procedure.

---

## G

### Grafana
Open-source observability and visualization platform deployed in the `monitoring` namespace on the Agora EKS cluster. Grafana provides dashboards for: pipeline consumer lag, processing latency, error rates, DLQ depth, throughput, anomaly scores, and Kafka Connect task status. Datasource: Prometheus (in-cluster) and Amazon Managed Prometheus.

---

## H

### HorizontalPodAutoscaler (HPA)
A Kubernetes resource that automatically scales the number of pod replicas based on observed metrics. Agora uses HPA with three metric types: CPU utilization, memory utilization, and custom Kafka consumer lag metrics. HPA configuration includes stabilization windows (scale-down delay of 300s) and aggressive scale-up policies (100% increase per 15s interval).

---

## I

### IAM Access Control
AWS IAM-based authentication for MSK Kafka, used on port 9098 instead of mTLS. Each pod inherits Kafka permissions from its Kubernetes ServiceAccount via **IRSA**. No passwords, certificates, or secrets to manage. The IAM policy controls which Kafka actions (Connect, Read, Write, Describe) are allowed on which topics.

### IRSA (IAM Roles for Service Accounts)
An AWS feature that allows Kubernetes pods to assume IAM roles. A ServiceAccount is annotated with the ARN of an IAM role. When a pod uses that ServiceAccount, it receives temporary AWS credentials (via OIDC federation) that grant the permissions of the associated IAM role. Agora uses IRSA for all MSK Kafka access, S3 access, and Secrets Manager access.

### Istio
An open-source service mesh platform that provides traffic management, security, and observability for Kubernetes workloads. Agora uses Istio to enforce zero-trust networking: STRICT mTLS between all pods, JWT-based request authentication, and deny-by-default authorization with per-service allow rules. Istio deploys a sidecar Envoy proxy alongside each pod, intercepting all network traffic at the application layer.

### Istio AuthorizationPolicy
A Kubernetes CRD that defines access control rules at the service mesh layer. Agora uses a deny-by-default model: a global `deny-all` AuthorizationPolicy blocks all traffic, and per-service policies selectively allow traffic from specific SPIFFE identities. AuthorizationPolicy operates at layer 7 (HTTP methods, paths) and layer 4 (source principals, namespaces).

### Istio PeerAuthentication
A Kubernetes CRD that defines mTLS mode for workloads in a namespace. Agora sets `mode: STRICT` on both `city-services` and `inventors` namespaces — all pod-to-pod traffic must use mutual TLS. The `istio-system` namespace uses `mode: PERMISSIVE` to allow ingress gateways to accept non-mTLS connections.

---

## K

### Kafka Connect
A distributed data integration framework running on EKS (`city-services` namespace) for streaming data between Kafka and other systems. Agora uses Kafka Connect with S3 Sink connectors to archive raw Kafka topics to the S3 data lake in AVRO format. Connector configuration: flush every 10,000 messages or 1 hour, partitioned by `year/month/day/hour`.

### Karpenter
An open-source Kubernetes node auto-scaler that replaces the standard Cluster Autoscaler. Karpenter launches the right EC2 instances for pending pods within seconds, handles spot interruption, consolidates under-utilized nodes, and manages node lifecycle. In Agora, Karpenter manages EKS worker nodes across all environments with configurable min/max node counts.

### KMS (AWS Key Management Service)
AWS service for creating and managing encryption keys. Agora uses a single KMS CMK (Customer Master Key) per environment for all encryption at rest: MSK Kafka topics, Aurora databases, S3 objects, EBS volumes, and Secrets Manager secrets.

### Kustomize
A Kubernetes configuration management tool that allows customization of raw Kubernetes YAML manifests using overlays and patches. Agora uses Kustomize with a base directory containing standard manifests and overlay directories for environment-specific customizations (dev, staging, production).

---

## M

### mTLS (Mutual TLS)
A security protocol where both the client and server present TLS certificates to authenticate each other. Agora uses mTLS at two layers:
1. **Device-to-gateway**: IoT devices authenticate to the gateway with client certificates.
2. **Service mesh (Istio)**: All pod-to-pod communication uses STRICT mTLS via Istio PeerAuthentication. Each Envoy proxy presents a SPIFFE-issued certificate. Connections without a valid client certificate are rejected at the proxy level.

Agora chose **IAM Access Control** over mTLS for Kafka because: no certificate rotation overhead, no secrets to manage, native AWS SDK integration, and audit trail via CloudTrail.

### Multi-tenancy
The architectural pattern of isolating multiple tenants (internal city services and external inventors) on the same infrastructure. Agora enforces multi-tenancy at multiple layers: Kubernetes namespaces, network policies (default-deny), RBAC, resource quotas, data access control (anonymized vs raw data), and API rate limiting.

### MSK Express (Amazon MSK Express)
A managed Kafka service by AWS with significantly better performance than the Standard MSK tier: 3x throughput per broker, 20x faster scaling, 90% faster recovery, and auto-scaling storage. Agora uses MSK Express for staging and production environments. It supports IAM auth, auto-recovery within 2 minutes, and requires 3 brokers across 3 AZs.

### MSK Serverless (Amazon MSK Serverless)
A pay-per-use tier of AWS MSK with no cluster management. Agora uses MSK Serverless for the dev environment — there are no brokers to provision, no instance types to choose, and it auto-scales from 0 to 200 MBps throughput. Limitations include 5 MBps per partition shard and no custom configuration options.

---

## O

### OIDC (OpenID Connect)
An authentication protocol that allows Kubernetes service accounts to assume AWS IAM roles (IRSA). Agora's EKS cluster has an OIDC identity provider configured, enabling the trust relationship between pods and IAM roles without needing static credentials.

---

## P

### P99 Latency
The 99th percentile of processing latency — 99% of requests complete within this time. Agora's primary SLO is P99 latency < 100ms for traffic-optimizer processing. Measured via custom Prometheus histograms (`processing_latency_seconds_bucket`). P99 is used instead of average because it better captures tail latency experienced by end users.

### Pod Anti-Affinity
A Kubernetes scheduling rule that prevents pods of the same service from being scheduled on the same node (or AZ). Agora uses `preferredDuringSchedulingIgnoredDuringExecution` anti-affinity on all services to spread pods across nodes and AZs, improving fault tolerance.

### PodDisruptionBudget (PDB)
A Kubernetes resource that limits the number of pods in a deployment that can be voluntarily disrupted at a time (e.g., during rolling updates or node maintenance). Agora configures PDBs for all critical services (e.g., traffic-optimizer: minAvailable 2, data-broker: minAvailable 3).

### PodMonitor
A custom resource definition (CRD) used by the Prometheus Operator to scrape metrics from pods. Similar to **ServiceMonitor** but targets pods directly by label selector rather than going through a Service. Used in Agora for scraping Kafka client metrics from stream processor pods.

### Priority Class
A Kubernetes resource that assigns priority levels to pods, determining which pods are evicted first during resource contention. Agora uses priority classes to ensure critical system pods (traffic-optimizer, data-broker) are preferred over less critical workloads during node pressure.

### Prometheus
An open-source systems monitoring and alerting toolkit deployed in the `monitoring` namespace on the Agora EKS cluster. Prometheus scrapes metrics from all microservices via **ServiceMonitor** and **PodMonitor** CRDs, evaluates alerting rules (consumer lag, latency, error rates), and stores metrics for Grafana visualization.

---

## R

### Rolling Update
The default Kubernetes deployment update strategy where old pods are gradually replaced with new pods. Agora uses rolling updates with `maxSurge=1` (one extra pod during update) and `maxUnavailable=0` (no downtime) for all stream processors.

### RPO (Recovery Point Objective)
The maximum acceptable amount of data loss measured in time. Agora defines tiered RPO targets: **safety-critical: 0** (no data loss via WAL streaming), **city-operational: 1 minute** (via Kafka consumer lag within processing window), **convenience: 7 days** (for non-critical services), **cross-region: 5 minutes** (via S3 CRR + Aurora Global DB lag). The platform-wide target is **5 minutes** — achieved through Kafka retention, S3 Sink connector, Aurora WAL streaming, and automated snapshots.

### RTO (Recovery Time Objective)
The maximum acceptable time to restore service after a disaster. Agora defines tiered RTO targets: **safety-critical: 30 seconds** (via Aurora failover + Istio mTLS recovery), **city-operational: 5 minutes** (via Karpenter node provisioning + EKS pod recovery), **convenience: 30 minutes** (for non-critical services), **cross-region: 4 hours** (full region rebuild). The platform-wide target is **15 minutes** — achieved through Aurora failover, MSK Express auto-recovery, Karpenter node provisioning, and defined DR runbooks. RTO targets are configured in the DR ConfigMap (`dr.rto.*` keys).

---

## S

### S3 Data Lake
Amazon S3 buckets used as the long-term storage layer for Kafka archives, processed data, logs, and backups. Agora uses 4 buckets per environment: data-lake, app-logs, access-logs, and backups. Lifecycle policies transition data from Standard → Intelligent-Tiering → Glacier → deletion.

### S3 Sink
A Kafka Connect connector that writes Kafka topic data to S3 in AVRO format. Agora deploys S3 Sink connectors for each raw topic (`vehicle.telemetry`, `sensor.environmental`, `signal.events`, `incidents`). Data is partitioned by hour in the S3 bucket path: `raw/{topic}/year=YYYY/month=MM/day=DD/hour=HH/`.

### Schema Registry
A Confluent service (deployed on EKS in `city-services` namespace) that stores and manages AVRO schemas for Kafka topics. Producers register schemas before writing; consumers retrieve schemas to deserialize. Supports compatibility modes (BACKWARD, FORWARD, FULL, NONE) to enforce safe schema evolution. Runs 2–6 pods with local schema cache for read-only fallback.

### SPIFFE Identity
Secure Production Identity Framework for Everyone — a standard for identity in dynamic environments. Istio issues each pod a SPIFFE identity in the format `spiffe://cluster.local/ns/<namespace>/sa/<service-account>`. This identity is embedded in the mTLS certificate and used by Istio AuthorizationPolicy to authenticate and authorize requests between services. For example, traffic-optimizer's SPIFFE identity is `spiffe://cluster.local/ns/city-services/sa/default`.

### State Serial
A monotonically increasing integer in the Terraform state file that tracks the number of state modifications. Each successful `terraform apply` increments the serial. The serial is critical for force-unlock safety: if the serial has advanced since the lock was acquired, the apply may have partially succeeded and force-unlocking could trigger drift remediation that destroys infrastructure.

### Service Level Objective (SLO)
A target level of reliability for a service. Agora's SLOs: traffic-optimizer P99 latency ≤ 100ms at 99.9%, event processing availability at 99.95%, API gateway uptime at 99.99%, data durability at 100%. Error budget for the 28-day window is calculated from the SLO target.

### ServiceMonitor
A custom resource definition (CRD) used by the Prometheus Operator to define how to scrape metrics from Kubernetes Services. Agora uses ServiceMonitors to configure Prometheus to scrape metrics from each service (traffic-optimizer, energy-management, data-broker, etc.).

### Stream Processor
A Kafka Streams application that reads from input topics, processes the data, and writes to output topics. Agora runs 4 stream processors in the `city-services` namespace: **Traffic Optimizer**, **Anomaly Detector**, **Energy Optimizer**, and **Data Broker**. Each processor has its own consumer group, HPA configuration, and SLO targets.

---

## T

### Timestream (Amazon Timestream)
AWS-managed time-series database service. In Agora, Timestream is used for sensor metric storage and analytical queries on time-series data from environmental sensors and vehicle telemetry.

### Traffic Optimizer
A Kafka Streams processor that reads from `vehicle.telemetry` and `signal.events` topics and produces commands to `signal.commands` and incident reports to `incidents`. Uses a 5-second sliding window with queue thresholds and green phase extension logic. Runs 3–10 pods in the `city-services` namespace. This is the most latency-sensitive processor with an SLO of P99 < 100ms.

### Terraform State Lock
A DynamoDB-based locking mechanism that prevents concurrent Terraform operations on the same state file. When `terraform apply` runs, it writes a lock item to the `terraform-lock` table. The lock includes the operation type, who acquired it, and a timestamp. Stale locks (held > 15 minutes) trigger a CloudWatch alarm and must be force-unlocked following the safe procedure. The lock table has PITR enabled, KEYS_ONLY streams, and TTL-based auto-expiration.

---

## V

### VPC Endpoint
An AWS networking construct that allows private connectivity between a VPC and AWS services without traversing the public internet. Agora uses VPC endpoints for: S3 (Gateway), ECR API/DKR (Interface), Secrets Manager (Interface), CloudWatch (Interface), CloudWatch Logs (Interface), and Amazon Managed Prometheus (Interface). VPC endpoints keep all AWS API traffic within the AWS network.

---

## W

### Woven City
Toyota's prototype "city of the future" at the base of Mount Fuji in Susono, Shizuoka Prefecture, Japan. Woven City is a living laboratory for smart city technologies, including autonomous vehicles, smart homes, AI-powered services, and IoT infrastructure. The **Agora** platform serves as the operating system for this city, managing data from 10,000+ connected devices.

---

## Numerical

### 3 Availability Zones
The Agora platform is deployed across 3 AWS Availability Zones to achieve 99.95% availability. MSK Express requires 3 AZs, Aurora Multi-AZ requires at least 2, and EKS control plane is multi-AZ by default. Losing 1 AZ is fully tolerated.

### 60,000+ events/second
The peak throughput target for the Agora platform, generated by 10,000+ IoT devices including autonomous vehicles, environmental sensors, traffic signals, and building management systems in Woven City.

---

## Appendix: Acronym Quick Reference

| Acronym | Full Name |
|---------|-----------|
| ACU | Aurora Capacity Unit |
| ALB | Application Load Balancer |
| AMP | Amazon Managed Prometheus |
| API | Application Programming Interface |
| AVRO | Apache Avro (data serialization format) |
| AZ | Availability Zone |
| CIDR | Classless Inter-Domain Routing |
| CMK | Customer Master Key (KMS) |
| CRD | Custom Resource Definition |
| CRR | Cross-Region Replication |
| DLQ | Dead Letter Queue |
| DR | Disaster Recovery |
| EBS | Elastic Block Store |
| ECR | Elastic Container Registry |
| EKS | Elastic Kubernetes Service |
| GW | Gateway |
| HA | High Availability |
| HPA | Horizontal Pod Autoscaler |
| IaC | Infrastructure as Code |
| IAM | Identity and Access Management |
| IGW | Internet Gateway |
| IRSA | IAM Roles for Service Accounts |
| ISR | In-Sync Replica |
| JWT | JSON Web Token |
| KMS | Key Management Service |
| mTLS | Mutual Transport Layer Security |
| MSK | Managed Streaming for Kafka |
| NAT | Network Address Translation |
| NATGW | NAT Gateway |
| OIDC | OpenID Connect |
| P1/P2/P3 | Priority 1/2/3 (incident severity) |
| P99 | 99th Percentile |
| PDB | Pod Disruption Budget |
| PII | Personally Identifiable Information |
| PITR | Point-in-Time Recovery |
| PSS | Pod Security Standards |
| PVC | Persistent Volume Claim |
| RBAC | Role-Based Access Control |
| RDS | Relational Database Service |
| RI | Reserved Instance |
| RPO | Recovery Point Objective |
| RTO | Recovery Time Objective |
| S3 | Simple Storage Service |
| SASL | Simple Authentication and Security Layer |
| SPIFFE | Secure Production Identity Framework for Everyone |
| SG | Security Group |
| SLA | Service Level Agreement |
| SLI | Service Level Indicator |
| SLO | Service Level Objective |
| SNS | Simple Notification Service |
| SSE | Server-Side Encryption |
| SSL | Secure Sockets Layer |
| TAM | Technical Account Manager |
| TLS | Transport Layer Security |
| VPC | Virtual Private Cloud |
| WAF | Web Application Firewall |
| WAL | Write-Ahead Log |
| WORM | Write Once, Read Many |
