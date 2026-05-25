# Deployment Guide — Agora Platform

> **Step-by-step deployment instructions for the Woven City Agora infrastructure across dev/staging/production environments**
> **Last Updated**: May 2026

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Quick Start: Deploy Everything](#2-quick-start-deploy-everything)
3. [Deployment Sequence](#3-deployment-sequence)
4. [Phase 1: Terraform IaC Deployment](#4-phase-1-terraform-iac-deployment)
5. [Phase 2: Kubernetes Deployment](#5-phase-2-kubernetes-deployment)
6. [Phase 3: Data Pipeline Deployment](#6-phase-3-data-pipeline-deployment)
7. [Environment-Specific Procedures](#7-environment-specific-procedures)
8. [Rollback Procedures](#8-rollback-procedures)
9. [Verification](#9-verification)
10. [CI/CD Integration](#10-cicd-integration)

---

## 1. Prerequisites

### Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.0 | Infrastructure provisioning |
| AWS CLI | >= 2.0 | AWS API interactions |
| kubectl | >= 1.28 | Kubernetes management |
| kustomize | >= 5.0 | K8s manifest overlays |
| istioctl | >= 1.21 | Istio service mesh installation and debugging |
| Helm (optional) | >= 3.0 | Package management |
| Python | >= 3.11 | Stream processors |
| Docker | >= 24.0 | Container builds |
| Java | >= 11 | Kafka CLI tools (kafka-topics, etc.) |

### AWS Pre-requisites

```bash
# 1. Configure AWS credentials
aws configure
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region: ap-northeast-1
# Default output format: json

# 2. Verify access
aws sts get-caller-identity
# Should return: Account, Arn, UserId

# 3. Request EC2 instance limit increase (production)
# Go to: AWS Console → EC2 → Limits → m7g.xlarge
# Request: 100 instances (for max scaling headroom)
```

### Required IAM Permissions

The deploying user needs:
- `AdministratorAccess` (or equivalent) for initial setup
- After bootstrap, use the Terraform state IAM role for automated deployments

---

## 2. Quick Start: Deploy Everything

```bash
# ===== ONE-TIME SETUP =====
# Clone repository
git clone git@github.com:woven-by-toyota/agora-infrastructure.git
cd agora-infrastructure

# Initialize Terraform backend (S3 + DynamoDB)
make init-bootstrap

# Verify prerequisites
make validate-prereqs

# ===== DEPLOY PHASE 1 (Terraform IaC) =====
# Deploy dev environment
make deploy ENV=dev PHASE=1

# Deploy staging environment
make deploy ENV=staging PHASE=1

# Deploy production environment
make deploy ENV=production PHASE=1

# ===== CONFIGURE KUBERNETES =====
# Update kubeconfig
make kubeconfig ENV=production
# aws eks update-kubeconfig --name agora-production --region ap-northeast-1

# ===== DEPLOY PHASE 2 (Kubernetes) =====
kustomize build kustomization/overlays/production | kubectl apply -f -

# ===== DEPLOY PHASE 3 (Data Pipeline) =====
make deploy-pipeline ENV=production

# ===== VERIFY =====
make verify ENV=production
```

---

## 3. Deployment Sequence

```
Bootstrap S3 + DynamoDB (one-time)
        │
        ▼
   Phase 1: Terraform IaC
   ┌──────────────────────────────┐
   │ 1. VPC + IAM                │  Foundation
   │ 2. EKS                      │  Compute
   │ 3. MSK                      │  Streaming
   │ 4. RDS (Aurora)             │  Database
   │ 5. S3                       │  Storage
   │ 6. Monitoring               │  Observability
   └──────────────────────────────┘
        │
        ▼
   Phase 2: Kubernetes
   ┌──────────────────────────────┐
   │ 1. Namespaces               │
   │ 2. RBAC                     │
   │ 3. Network Policies         │
   │ 4. Resource Quotas          │
   │ 5. Istio Service Mesh       │  ← mTLS, authz, sidecar
   │ 6. DR Components            │  ← backup CronJob, config
   │ 7. Core Services            │
   │ 8. Monitoring (Prometheus)  │
   └──────────────────────────────┘
        │
        ▼
   Phase 3: Data Pipeline
   ┌──────────────────────────────┐
   │ 1. Kafka Topics + AVRO      │
   │ 2. Schema Registry          │
   │ 3. Kafka Connect S3 Sink    │
   │ 4. Stream Processors        │
   │ 5. IAM Auth (IRSA)          │
   │ 6. DLQ Processor            │
   │ 7. Pipeline Monitoring      │
   └──────────────────────────────┘
        │
        ▼
   Verification & Testing
```

---

## 4. Phase 1: Terraform IaC Deployment

### 4.1 Bootstrap State Backend (One-Time)

```bash
cd terraform/bootstrap

# Initialize
terraform init

# Plan
terraform plan -out=tfplan \
  -var="bucket_name=agora-terraform-state" \
  -var="dynamodb_table=terraform-lock" \
  -var="region=ap-northeast-1"

# Apply
terraform apply tfplan

# Verify
aws s3 ls s3://agora-terraform-state/
aws dynamodb describe-table --table-name terraform-lock
```

### 4.2 Deploy Root Module

```bash
cd terraform/environments/${ENV}

# Initialize with S3 backend
terraform init \
  -backend-config="bucket=agora-terraform-state" \
  -backend-config="key=${ENV}/terraform.tfstate" \
  -backend-config="region=ap-northeast-1" \
  -backend-config="encrypt=true" \
  -backend-config="dynamodb_table=terraform-lock"

# Create workspace
terraform workspace new ${ENV} 2>/dev/null || terraform workspace select ${ENV}

# Plan
terraform plan -out=tfplan -var-file=terraform.tfvars

# Review plan
terraform show tfplan | less

# Apply
terraform apply tfplan

# Verify outputs
terraform output
```

### 4.3 Deploy Individual Modules

For targeted deployments (e.g., updating only MSK):

```bash
terraform plan -target=module.msk -out=tfplan -var-file=terraform.tfvars
terraform apply tfplan
```

**Module dependency order:**
1. `module.vpc` (network foundation)
2. `module.iam` (IAM roles)
3. `module.eks` + `module.msk` + `module.rds` + `module.s3` (parallel)
4. `module.monitoring` (depends on all above)

### 4.4 Environment Variables Reference

| Variable | Dev | Staging | Prod |
|----------|-----|---------|------|
| `vpc_cidr` | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| `availability_zones` | 2 AZs | 3 AZs | 3 AZs |
| `msk_broker_type` | serverless | express | express |
| `msk_broker_count` | N/A | 3 | 3 |
| `msk_instance_type` | N/A | express.m7g.large | express.m7g.xlarge |
| `rds_instance_class` | db.serverless | db.r5.large | db.r6g.xlarge |
| `rds_reader_count` | 0 | 1 | 2 |
| `desired_node_count` | 2 | 4 | 8 |
| `min_node_count` | 1 | 3 | 5 |
| `max_node_count` | 5 | 12 | 30 |

### 4.5 Post-Terraform Steps

```bash
# Update kubeconfig
aws eks update-kubeconfig --name agora-${ENV} --region ap-northeast-1

# Verify cluster
kubectl cluster-info
kubectl get nodes

# Verify MSK bootstrap
aws kafka get-bootstrap-brokers --cluster-arn $(terraform output -raw msk_cluster_arn)

# Verify Aurora endpoint
terraform output aurora_endpoint
```

---

## 5. Phase 2: Kubernetes Deployment

### 5.1 Kustomize Deploy

```bash
# Build manifests for target environment
kustomize build kustomization/overlays/${ENV} > /tmp/agora-${ENV}.yaml

# Review
less /tmp/agora-${ENV}.yaml

# Dry-run
kubectl apply -f /tmp/agora-${ENV}.yaml --dry-run=client

# Apply
kubectl apply -f /tmp/agora-${ENV}.yaml

# Or apply directly (Kustomize native)
kubectl apply -k kustomization/overlays/${ENV}
```

### 5.2 Deploy Individual Component

```bash
# Deploy specific namespace
kubectl apply -f namespaces/city-services.yaml

# Deploy specific service
kubectl apply -k services/traffic-optimizer/

# Deploy monitoring
kubectl apply -k monitoring/
```

### 5.3 Istio Service Mesh Setup

Kustomize applies Istio resources as part of the base deployment (see [Istio resources reference](agora-kubernetes-components/docs/ARCHITECTURE.md#service-mesh-layer-istio)).

**Prerequisites:**

```bash
# 1. Install Istio CLI
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-1.21/bin:$PATH

# 2. Install Istio on EKS
istioctl install --set profile=default -y

# 3. Label namespaces for automatic sidecar injection
kubectl label namespace city-services istio-injection=enabled --overwrite
kubectl label namespace inventors istio-injection=enabled --overwrite
kubectl label namespace monitoring istio-injection=enabled --overwrite
```

**Verify injection:**

```bash
# Pods should show 2/2 containers (app + istio-proxy)
kubectl get pods -n city-services

# Verify Istio proxy status
istioctl proxy-status
```

### 5.4 DR Components

Disaster recovery resources deploy with the base kustomization:

```bash
# Verify DR ConfigMap
kubectl get configmap dr-config -n city-services -o yaml

# Verify backup CronJob (daily at 02:00 UTC)
kubectl get cronjob terraform-state-backup -n city-services

# Manually trigger backup test
kubectl create job --from=cronjob/terraform-state-backup manual-backup-test -n city-services
kubectl logs job/manual-backup-test -n city-services
```

### 5.5 Kustomize Overlay Customisation

```bash
# Development: minimal resources, port-forward only
kustomize build kustomization/overlays/development

# Staging: reduced replicas, internal ALB
kustomize build kustomization/overlays/staging

# Production: full replicas, strict affinity, WAF
kustomize build kustomization/overlays/production
```

### 5.6 Post-Deploy Verification

```bash
# Check pods (verify 2/2 for Istio-injected services)
kubectl get pods --all-namespaces

# Check services
kubectl get svc --all-namespaces

# Check HPAs
kubectl get hpa --all-namespaces

# Check PDBs
kubectl get pdb --all-namespaces

# Check network policies
kubectl get networkpolicy --all-namespaces

# Check Istio mesh
istioctl proxy-status
kubectl get peerauthentication --all-namespaces
kubectl get authorizationpolicy --all-namespaces

# Check DR readiness
kubectl get cronjob terraform-state-backup -n city-services
kubectl get configmap dr-config -n city-services

# Test connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot -- /bin/bash
# Inside: curl traffic-optimizer.city-services:8080/health/live
```

---

## 6. Phase 3: Data Pipeline Deployment

### 6.1 Create Kafka Topics

```bash
# From a pod with Kafka CLI tools, or a dedicated job
kubectl run kafka-admin --image=bitnami/kafka:3.6 --rm -it -- /bin/bash

# Apply topic definitions (from definitions.yaml)
kafka-topics.sh --create \
  --topic vehicle.telemetry \
  --partitions 12 \
  --replication-factor 3 \
  --config cleanup.policy=delete,compact \
  --config retention.ms=604800000 \
  --config compression.type=snappy \
  --config min.insync.replicas=2 \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --command-config /etc/kafka/admin.properties

# Verify
kafka-topics.sh --describe --topic vehicle.telemetry \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098

# Bulk create via script
scripts/create-topics.sh ${ENV}
```

### 6.2 Register AVRO Schemas

```bash
# Register with Schema Registry
curl -X POST http://schema-registry:8081/subjects/vehicle.telemetry-value/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d @kafka-topics/vehicle.telemetry.schema.avsc

# Verify
curl http://schema-registry:8081/subjects | jq .
```

### 6.3 Deploy Schema Registry

```bash
kubectl apply -f schema-registry/
```

### 6.4 Deploy Kafka Connect

```bash
# Deploy Connect workers
kubectl apply -f kafka-connect/

# Wait for workers to be ready
kubectl wait --for=condition=ready pod -l app=kafka-connect -n city-services --timeout=300s

# Verify
curl http://kafka-connect:8083/

# Deploy S3 sink connectors
curl -X POST http://kafka-connect:8083/connectors \
  -H "Content-Type: application/json" \
  -d @kafka-connect/connectors/s3-sink-vehicle-telemetry.json

# Verify connectors
curl http://kafka-connect:8083/connectors/
curl http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/status
```

### 6.5 Deploy Stream Processors

```bash
# Build container images (in each processor directory)
docker build -t agora/traffic-optimizer:latest stream-processors/traffic-optimizer/
docker push agora/traffic-optimizer:latest

# Deploy each processor
kubectl apply -f stream-processors/traffic-optimizer/
kubectl apply -f stream-processors/anomaly-detector/
kubectl apply -f stream-processors/energy-optimizer/
kubectl apply -f stream-processors/data-broker/

# Wait for ready
kubectl wait --for=condition=ready pod -l app=traffic-optimizer -n city-services
kubectl wait --for=condition=ready pod -l app=anomaly-detector -n city-services
kubectl wait --for=condition=ready pod -l app=energy-optimizer -n city-services
kubectl wait --for=condition=ready pod -l app=data-broker -n city-services
```

### 6.6 Deploy DLQ Processor

```bash
kubectl apply -f dead-letter-queue/
```

### 6.7 Apply IAM Auth (IRSA)

```bash
kubectl apply -f iam/service-accounts.yaml

# Verify IRSA annotation
kubectl get sa traffic-optimizer -n city-services -o yaml | grep eks.amazonaws.com/role-arn
```

### 6.8 Data Pipeline Monitoring

```bash
kubectl apply -f monitoring/
```

---

## 7. Environment-Specific Procedures

### 7.1 Dev Environment

```bash
# Deploy (minimal cost)
cd terraform/environments/dev
terraform init && terraform apply -var-file=terraform.tfvars

# Skip Karpenter (use managed node group for simplicity)
# MSK is Serverless — no brokers to provision
# Aurora is Serverless v2 — 0.5 to 2 ACU

# K8s: port-forward for local testing
kubectl port-forward svc/api-gateway 8080:8080 -n city-services
```

**Dev environment cost**: ~$200/month (mostly EKS nodes + NAT GW)

### 7.2 Staging Environment

```bash
# Deploy (moderate scale)
cd terraform/environments/staging
terraform init && terraform apply -var-file=terraform.tfvars

# Load test: simulate production traffic
scripts/seed-test-data.sh staging 50000

# Verify scaling behaviour
kubectl get hpa --watch
```

**Staging environment cost**: ~$3,000/month

### 7.3 Production Environment

```bash
# Deploy (full scale)
cd terraform/environments/production
terraform init

# Plan — requires approval
terraform plan -out=tfplan -var-file=terraform.tfvars
terraform show tfplan

# Apply — requires admin approval
terraform apply tfplan

# Verify everything twice
make verify ENV=production
scripts/test-end-to-end.sh production
```

**Production environment cost**: ~$16,200/month

### 7.4 Production Deployment Checklist

```markdown
## Pre-Deployment
- [ ] Notify team via Slack (#agora-deployments)
- [ ] Verify CI/CD pipeline status (all green)
- [ ] Check current RDS backup (manual snapshot)
- [ ] Verify Terraform plan reviewed by peer
- [ ] Check MSK cluster health (all brokers ACTIVE)
- [ ] Check EKS cluster health (all nodes Ready)
- [ ] Check Terraform state lock table health (no stale locks)
- [ ] Istio proxy-status: all proxies synced
- [ ] Verify DR ConfigMap and backup CronJob exist
- [ ] Enable read-only mode? (if required)

## Deployment
- [ ] Run: terraform apply
- [ ] Monitor: CloudWatch alarm (expect brief anomalies)
- [ ] Verify: kubectl get pods --all-namespaces (all Running, 2/2 for Istio-injected)
- [ ] Verify: istioctl proxy-status (all SYNCED)
- [ ] Verify: test-end-to-end.sh production
- [ ] Verify: latency dashboard (P99 < 100ms baseline)
- [ ] Verify: DR readiness dashboard (backup age, consumer lag within RPO)

## Post-Deployment
- [ ] Verify: SNS alerts not firing unexpectedly (including dr topic)
- [ ] Verify: DR backup CronJob ran successfully (check logs)
- [ ] Create manual RDS snapshot
- [ ] Verify: Istio mTLS handshake success rate dashboard > 99%
- [ ] Notify team via Slack (#agora-deployments ✅)
- [ ] Update deployment log
```

---

## 8. Rollback Procedures

### 8.1 Terraform Rollback

```bash
# Option A: Revert to previous Terraform version
# Previous tfplan saved with timestamp
terraform apply tfplan.20260516-140000

# Option B: Target specific module rollback
terraform apply -target=module.eks -var-file=terraform.tfvars

# Option C: Full state rollback (S3 versioning)
# 1. Find previous state version
aws s3api list-object-versions \
  --bucket agora-terraform-state \
  --key production/terraform.tfstate

# 2. Download and push
aws s3api get-object \
  --bucket agora-terraform-state \
  --key production/terraform.tfstate \
  --version-id <PreviousVersionId> \
  /tmp/terraform.tfstate.rollback
terraform state push /tmp/terraform.tfstate.rollback
```

### 8.2 Kubernetes Rollback

```bash
# Option A: Rollback Kustomize (apply previous overlay version)
git checkout HEAD~1 -- kustomization/
kustomize build kustomization/overlays/production | kubectl apply -f -

# Option B: Rollback specific deployment
kubectl rollout undo deployment/traffic-optimizer -n city-services

# Option C: Rollback with version
kubectl rollout undo deployment/traffic-optimizer -n city-services --to-revision=3

# Check rollout history
kubectl rollout history deployment/traffic-optimizer -n city-services
```

### 8.3 Data Pipeline Rollback

```bash
# Option A: Restart connector with previous config
curl -X POST http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/restart

# Option B: Revert to previous connector config (versioned)
curl -X PUT http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/config \
  -H "Content-Type: application/json" \
  -d '{"connector.class": "...", ...previous config...}'

# Option C: Reset consumer group offset (skip bad messages)
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group traffic-optimizer-group \
  --topic vehicle.telemetry \
  --reset-offsets --to-latest --execute
```

---

## 9. Verification

### 9.1 Smoke Test Script

```bash
#!/bin/bash
# scripts/smoke-test.sh
# Quick verification after deployment

ENV=${1:-dev}
echo "=== Smoke Test: agora-${ENV} ==="

# EKS
echo "1. EKS cluster..."
kubectl cluster-info | head -3
kubectl get nodes -o wide

# Namespaces
echo "2. Namespaces..."
kubectl get namespaces city-services inventors monitoring

# Services
echo "3. Core services..."
kubectl get pods -n city-services
kubectl get svc -n city-services

# MSK
echo "4. MSK cluster..."
aws kafka list-clusters --query "ClusterInfoList[?ClusterName=='agora-${ENV}'].State"
kafka-topics.sh --list --bootstrap-server b-1:9098,b-2:9098,b-3:9098

# Aurora
echo "5. Aurora cluster..."
aws rds describe-db-clusters --db-cluster-identifier agora-${ENV} \
  --query 'DBClusters[0].Status'

# S3
echo "6. S3 buckets..."
aws s3 ls | grep agora-${ENV}

# Monitoring
echo "7. Monitoring..."
kubectl get pods -n monitoring

echo "=== Smoke test complete ==="
```

### 9.2 End-to-End Test

```bash
# Full integration test
scripts/test-end-to-end.sh ${ENV}

# Expected output:
# ✅ Producer connected
# ✅ 1000 messages produced to vehicle.telemetry
# ✅ Consumer lag < 100
# ✅ signal.commands has commands
# ✅ incidents has no false positives
# ✅ S3 archive created within 60 seconds
# ✅ Anonymized data has no PII
# ✅ DLQ is empty
```

---

## 10. CI/CD Integration

### 10.1 GitHub Actions (Terraform)

```yaml
# .github/workflows/terraform.yml
name: Terraform
on:
  push:
    branches: [main]
    paths: ['terraform/**']
  pull_request:
    paths: ['terraform/**']

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - name: Format check
        run: terraform fmt -check -recursive terraform/

      - name: Init
        run: terraform init -backend=false terraform/

      - name: Validate
        run: terraform validate terraform/

  plan:
    needs: validate
    environment: ${{ github.ref_name }}
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT:role/TerraformPlanRole

      - name: Init
        run: terraform init terraform/environments/${{ github.ref_name }}

      - name: Plan
        run: terraform plan -no-color -out=tfplan
```

### 10.2 Makefile Targets

```makefile
.PHONY: deploy plan validate kubeconfig verify

# Deploy all infrastructure
deploy:
	cd terraform/environments/$(ENV) && \
		terraform init && \
		terraform apply -auto-approve -var-file=terraform.tfvars

# Plan-only
plan:
	cd terraform/environments/$(ENV) && \
		terraform plan -out=tfplan -var-file=terraform.tfvars

# Validate all Terraform
validate:
	terraform fmt -check -recursive terraform/
	terraform init -backend=false terraform/ && terraform validate terraform/

# Update kubeconfig
kubeconfig:
	aws eks update-kubeconfig --name agora-$(ENV) --region ap-northeast-1

# Full verification
verify:
	scripts/smoke-test.sh $(ENV)
	scripts/test-end-to-end.sh $(ENV)

# Deploy data pipeline
deploy-pipeline:
	kubectl apply -f schema-registry/
	kubectl apply -f kafka-connect/
	kubectl apply -f stream-processors/traffic-optimizer/
	kubectl apply -f stream-processors/anomaly-detector/
	kubectl apply -f stream-processors/energy-optimizer/
	kubectl apply -f stream-processors/data-broker/
	kubectl apply -f dead-letter-queue/
```
