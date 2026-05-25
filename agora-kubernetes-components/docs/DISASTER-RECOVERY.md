# Disaster Recovery

## Overview

This document covers backup and recovery procedures for the Agora Kubernetes platform. Recovery objectives:

| Metric | Target |
|--------|--------|
| RPO (Recovery Point Objective) | 1 hour |
| RTO (Recovery Time Objective) | 30 minutes |
| RTO (full cluster loss) | 2 hours |

## Backup Strategy

### Etcd Snapshots

Etcd backs up all Kubernetes resource state (deployments, services, configmaps, secrets, etc.).

```bash
# Manual snapshot (if you have direct etcd access)
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# For EKS managed etcd: AWS handles automated backups
# You can restore from a specific point-in-time via cluster operations
```

**Frequency**: Every 30 minutes (automated via CronJob or cloud provider).

### PVC Backups

Persistent data (Prometheus TSDB, Grafana data) should be backed up.

```bash
# Backup Prometheus data
kubectl exec -n monitoring deployment/prometheus -- tar czf - /prometheus > prometheus-backup.tar.gz

# Or use Velero for automated PVC backups
velero backup create agora-backup --include-namespaces city-services,inventors,monitoring
```

**Recommended tools**: Velero (velero.io) for Kubernetes-native backup and restore of PVCs and resources.

### GitOps State

All Kubernetes manifests are stored in this repository. This is the source of truth for all resources.

```bash
# Always keep the repo up to date
git pull

# Manifests are the recovery source
ls -la kustomization/
```

## Recovery Procedures

### Scenario 1: Single Pod/Deployment Failure

```bash
# Check what went wrong
kubectl describe deployment <name> -n city-services

# Force restart
kubectl rollout restart deployment/<name> -n city-services

# Scale down and up if stuck
kubectl scale deployment/<name> --replicas=0 -n city-services
kubectl scale deployment/<name> --replicas=<desired> -n city-services
```

**RTO**: < 1 minute

### Scenario 2: Namespace Deletion

```bash
# Recreate from manifests (Kustomize)
kubectl apply -k kustomization/

# Or for a specific namespace
kubectl apply -f kustomization/namespaces/city-services.yaml
kubectl apply -k kustomization/
```

**RTO**: < 5 minutes

### Scenario 3: Full Cluster Loss

```bash
# 1. Provision a new EKS cluster (Terraform or eksctl)
eksctl create cluster -f cluster.yaml

# 2. Install prerequisites
#    - AWS Load Balancer Controller
#    - Prometheus Operator
#    - metrics-server
#    - IRSA for data-broker

# 3. Deploy all manifests
kubectl apply -k kustomization/overlays/production/

# 4. Restore PVCs (if backed up with Velero)
velero restore create --from-backup agora-backup

# 5. Verify
kubectl get pods -n city-services
kubectl get pods -n monitoring
```

**RTO**: < 2 hours (assuming cluster provisioning is automated)

### Scenario 4: Data Broker / Kafka Failure

```bash
# Check MSK cluster status in AWS console
# data-broker will automatically reconnect when MSK is available

# If consumer lag is too high:
# 1. Stop data-broker consumers
kubectl scale deployment/data-broker --replicas=0 -n city-services

# 2. Reset consumer group offset (from a Kafka client)
kafka-consumer-groups --bootstrap-server <msk-endpoint>:9098 \
  --group agora-data-broker --topic <topic> --reset-offsets --to-earliest \
  --execute

# 3. Restart data-broker
kubectl scale deployment/data-broker --replicas=5 -n city-services
```

## Prevention

1. **Always use Kustomize/Helm** for deployments — never `kubectl create` ad-hoc resources
2. **Enable PDBs** (already configured) to prevent downtime during node maintenance
3. **Use pod anti-affinity** (already configured) to spread replicas across availability zones
4. **Enable HPA** (already configured) to handle traffic spikes
5. **Regularly validate manifests**:
   ```bash
   ./scripts/validate.sh
   ```
