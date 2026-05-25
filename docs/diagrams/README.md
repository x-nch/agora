# Architecture Diagrams — Agora Platform

> **Index and descriptions for all architecture diagrams.**
> **Last Updated**: May 2026

*This document is maintained by the docs/diagram-architect agent.*

---

## Diagram Index

| Diagram | File | Format | Description |
|---------|------|--------|-------------|
| High-Level Architecture | [`high-level-architecture.svg`](../../diagrams/high-level-architecture.svg) | SVG (from DOT) | 6-layer application stack showing the complete Agora platform from IoT devices through inventor ecosystem |
| AWS Infrastructure | [`aws-infrastructure.svg`](../../diagrams/aws-infrastructure.svg) | SVG (from DOT) | VPC layout with 3 Availability Zones, subnet design, NAT Gateways, VPC Endpoints, and AWS service placement |
| End-to-End Data Flow | [`dataflow.svg`](../../diagrams/dataflow.svg) | SVG (from Mermaid) | Complete data flow from IoT devices through MSK Kafka, stream processors, to S3 data lake and output topics |
| Latency Timeline | [`latency-timeline.svg`](../../diagrams/latency-timeline.svg) | SVG (from Mermaid) | End-to-end processing latency Gantt chart showing timing from device produce through each processing stage |
| Istio Service Mesh | [`istio-service-mesh.mmd`](../../diagrams/istio-service-mesh.mmd) | MMD | Istio service mesh topology: istiod control plane, Envoy sidecars, STRICT mTLS between namespaces, inventor egress restrictions |
| DR Architecture | [`dr-architecture.mmd`](../../diagrams/dr-architecture.mmd) | MMD | Multi-region DR architecture: 3-AZ primary in ap-northeast-1, DR standby in ap-southeast-1, backup automation, stale lock detection |
| Terraform State Lock | [`terraform-state-lock.mmd`](../../diagrams/terraform-state-lock.mmd) | MMD (Sequence) | DynamoDB-based state lock flow: lock acquire, concurrent apply prevention, stale lock detection, force-unlock recovery |

## Source Files

Diagrams are generated from source files and committed as SVGs:

| Source Format | Files |
|---------------|-------|
| Graphviz (DOT) | `high-level-architecture.dot`, `aws-infrastructure.dot` |
| Mermaid (MMD) | `dataflow.mmd`, `latency-timeline.mmd`, `istio-service-mesh.mmd`, `dr-architecture.mmd`, `terraform-state-lock.mmd` |

### Regenerating Diagrams

```bash
# Graphviz DOT → SVG
dot -Tsvg diagrams/high-level-architecture.dot -o diagrams/high-level-architecture.svg
dot -Tsvg diagrams/aws-infrastructure.dot -o diagrams/aws-infrastructure.svg

# Mermaid → SVG (using mmdc CLI)
npx @mermaid-js/mermaid-cli mmdc -i diagrams/dataflow.mmd -o diagrams/dataflow.svg
npx @mermaid-js/mermaid-cli mmdc -i diagrams/latency-timeline.mmd -o diagrams/latency-timeline.svg
npx @mermaid-js/mermaid-cli mmdc -i diagrams/istio-service-mesh.mmd -o diagrams/istio-service-mesh.svg
npx @mermaid-js/mermaid-cli mmdc -i diagrams/dr-architecture.mmd -o diagrams/dr-architecture.svg
npx @mermaid-js/mermaid-cli mmdc -i diagrams/terraform-state-lock.mmd -o diagrams/terraform-state-lock.svg
```
