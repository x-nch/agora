# AGENTS.md — Agora Platform

## Repo structure

Monorepo with three independent projects (no shared toolchain):

| Directory | What | Tooling |
|---|---|---|
| `agora-infrastructure/` | Terraform IaC (VPC, EKS, MSK, Aurora, S3, IAM, KMS) | `terraform init/plan/apply` |
| `agora-kubernetes-components/` | Kustomize K8s manifests + Helm charts | `kustomize build`, `kubectl apply -k` |
| `agora-data-pipeline/` | Python Kafka stream processors + K8s manifests | Python 3.11, confluent-kafka |
| `docs/` | MkDocs documentation site | `mkdocs serve/build` |
| `inception/` | Original spec docs (requirements, not code) | Read-only reference |

## Key commands

### Phase 1 — Terraform
```bash
cd agora-infrastructure/terraform
terraform init && terraform plan && terraform apply
# Bootstrap backend first (one-time):
cd bootstrap && terraform init && terraform apply
# Environment-specific:
cd environments/dev && terraform plan
```

### Phase 2 — Kustomize
```bash
# Deploy all base resources:
kubectl apply -k agora-kubernetes-components/kustomization/base
# Or environment overlay:
kubectl apply -k agora-kubernetes-components/kustomization/overlays/production
```

### Phase 3 — Data pipeline
```bash
# Deploy all pipeline components:
agora-data-pipeline/scripts/deploy-pipeline.sh
# Create Kafka topics (requires MSK cluster):
agora-data-pipeline/kafka-topics/apply-topics.sh
# Seed test data:
agora-data-pipeline/scripts/seed-test-data.sh b-1:9098 1000
# End-to-end test:
agora-data-pipeline/scripts/test-end-to-end.sh
```

### Docs
```bash
mkdocs serve   # live preview at http://127.0.0.1:8000
mkdocs build   # static site to site/
```

## Critical gotchas

- **MSK IAM port is 9098** (not 9092). All Kafka bootstrap configs use `b-1:9098,b-2:9098,b-3:9098`.
- **No `pip install -r requirements.txt` at root** — each stream processor under `agora-data-pipeline/stream-processors/*/` has its own `requirements.txt` and Dockerfile.
- **All K8s resources deploy to `city-services` namespace** unless specified otherwise.
- **Terraform uses S3 backend** — bootstrap `terraform/bootstrap/` first to create the state bucket.
- **Kafka topic configs use `&` separators** (not newlines) in shell apply scripts — the `apply-topics.sh` script handles this.
- **AVRO schemas** are in `agora-data-pipeline/kafka-topics/` and referenced by stream processors via relative path `../../kafka-topics/`.
- **Stream processor Python code runs inside containers** — development/testing requires building Docker images first.
- **No test framework is configured** — the only test is `scripts/test-end-to-end.sh` which is a bash integration test.

## Architecture notes

- 3 Availability Zones in `ap-northeast-1`
- MSK Express (3 brokers), NOT Provisioned — 20x faster scaling, auto-recovery
- IAM Access Control via IRSA (not mTLS) — every pod inherits Kafka permissions from its K8s ServiceAccount
- Data broker has a 3-stage transform pipeline: `anonymizer.py → aggregator.py → access_control.py`
- 9 Kafka topics total (4 input, 3 output, 1 alerts, 1 DLQ)
- Replication factor is always 3
