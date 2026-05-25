# Getting Started — Agora Platform

> **Prerequisites, environment setup, and first deployment walkthrough for the Woven City Agora platform.**
> **Last Updated**: May 2026

---

## Overview

This guide walks through setting up the Agora platform from scratch — from tool installation to deploying a working smart city data pipeline. The platform is deployed in 3 phases:

1. **Phase 1: Infrastructure** (Terraform IaC) — VPC, EKS, MSK, Aurora, S3
2. **Phase 2: Kubernetes** (Kustomize) — Namespaces, RBAC, services, monitoring
3. **Phase 3: Data Pipeline** — Kafka topics, Schema Registry, stream processors

---

## Prerequisites

### Required Tools

| Tool | Minimum Version | Install Guide |
|------|----------------|---------------|
| Terraform | >= 1.0 | [terraform.io/downloads](https://www.terraform.io/downloads) |
| AWS CLI | >= 2.0 | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| kubectl | >= 1.28 | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| kustomize | >= 5.0 | `brew install kustomize` |
| Python | >= 3.11 | [python.org/downloads](https://www.python.org/downloads/) |
| Docker | >= 24.0 | [docker.com/get-started](https://www.docker.com/get-started/) |
| Java | >= 11 | For Kafka CLI tools |

### AWS Account Setup

1. AWS account with `AdministratorAccess` (or equivalent)
2. Default region: `ap-northeast-1` (Tokyo)
3. Request EC2 limit increase for `m7g.xlarge` (production: 100 instances)
4. Configure credentials: `aws configure`

### Repository Setup

```bash
git clone git@github.com:woven-by-toyota/agora-infrastructure.git
cd agora-infrastructure
```

---

## First Deployment

See the full [Deployment Guide](DEPLOYMENT_GUIDE.md) for detailed steps, or use the quick start:

```bash
# Phase 1: Bootstrap + Terraform
make init-bootstrap
make deploy ENV=dev PHASE=1

# Configure kubectl
make kubeconfig ENV=dev

# Phase 2: Kubernetes
kubectl apply -k kustomization/overlays/dev

# Phase 3: Data Pipeline
make deploy-pipeline ENV=dev

# Verify
make verify ENV=dev
```

---

## Next Steps

- Review the [Architecture](ARCHITECTURE.md) for a detailed understanding of the platform
- Read the [Deployment Guide](DEPLOYMENT_GUIDE.md) for environment-specific procedures
- Learn about [Security](SECURITY.md) architecture and best practices
- Familiarize yourself with the [Operations Runbook](OPERATIONS_RUNBOOK.md) for incident response
- Check the [Glossary](GLOSSARY.md) for terminology
