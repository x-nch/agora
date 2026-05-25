# EKS Module
# Creates an EKS cluster with managed node groups and Karpenter for autoscaling.

## What It Creates
- EKS cluster (private endpoint + limited public access for kubectl)
- Managed node group (initial node pool)
- Karpenter node autoscaler (installed via Helm)
- EKS addons: vpc-cni, kube-proxy, coredns, ebs-csi-driver
- OIDC provider (for IRSA)
- Cluster logging (audit, api, authenticator, controllerManager, scheduler)

## Required Inputs
| Variable | Type | Description |
|----------|------|-------------|
| `cluster_name` | `string` | EKS cluster name |
| `kubernetes_version` | `string` | K8s version |
| `vpc_id` | `string` | VPC ID |
| `subnet_ids` | `list(string)` | Private subnet IDs |
| `node_instance_types` | `list(string)` | EC2 instance types |
| `desired_size` | `number` | Desired nodes |
| `min_size` | `number` | Min nodes |
| `max_size` | `number` | Max nodes |

## Outputs
| Output | Description |
|--------|-------------|
| `cluster_endpoint` | Cluster API endpoint |
| `cluster_ca_certificate` | CA certificate |
| `cluster_arn` | Cluster ARN |
| `cluster_name` | Cluster name |
| `oidc_issuer_url` | OIDC issuer URL |
| `cluster_role_arn` | EKS cluster IAM role ARN |
| `node_role_arn` | EKS node IAM role ARN |

## Example
```hcl
module "eks" {
  source = "../modules/eks"

  environment           = "production"
  cluster_name         = "agora-production"
  kubernetes_version   = "1.28"
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnets
  node_instance_types = ["m7g.xlarge", "m7g.2xlarge"]
  desired_size        = 8
  min_size            = 5
  max_size            = 30
  cluster_role_arn    = module.iam.eks_cluster_role_arn
  node_role_arn       = module.iam.eks_node_role_arn
}
```
