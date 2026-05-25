# Kubernetes Add-ons Module
# Deploys essential cluster add-ons via Helm.

## What It Creates
| Add-on | Purpose | Namespace |
|--------|---------|-----------|
| NGINX Ingress Controller | HTTP/S ingress with NLB | `ingress-nginx` |
| cert-manager | TLS certificates via Let's Encrypt | `cert-manager` |
| ExternalDNS | Route53 DNS record management | `external-dns` |
| metrics-server | Resource metrics for HPA | `kube-system` |
| AWS Load Balancer Controller | ALB/NLB management | `kube-system` |

## Required Inputs
| Variable | Type | Description |
|----------|------|-------------|
| `environment` | `string` | Environment name |
| `eks_cluster_name` | `string` | EKS cluster name |

## Optional Inputs
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vpc_id` | `string` | `""` | VPC ID (for AWS LB Controller) |
| `acme_email` | `string` | `admin@agora.woven-city.jp` | Let's Encrypt contact email |

## Prerequisites
- EKS cluster must be running
- OIDC provider must be configured
- `kubernetes` and `helm` providers must be configured in root module
