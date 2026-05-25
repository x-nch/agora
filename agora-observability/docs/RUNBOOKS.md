# Runbooks

## 1. KafkaConsumerLagHigh

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: A Kafka consumer group is falling behind the producer. Lag > 1000 messages indicates the consumer cannot keep up with the production rate.

**Possible causes**: Consumer pod resource throttling, downstream service slow, consumer batch size too small, partition count mismatch, consumer rebalancing.

**Investigation**:
```bash
# Check consumer group lag
kubectl exec -n city-services deploy/kafka-consumer -- \
  kafka-consumer-groups --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group <group> --describe
# Check consumer pod metrics
kubectl -n city-services top pod -l app=kafka-consumer
# Check logs for errors
kubectl -n city-services logs -l app=kafka-consumer --tail=100
```

**Resolution**: Scale consumer pods `kubectl scale deploy/kafka-consumer --replicas=N`, increase CPU/memory limits, or optimize consumer batch processing.

---

## 2. KafkaBrokerDown

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: One or more MSK brokers are unreachable.

**Possible causes**: AWS AZ outage, MSK cluster update, network policy blocking, broker crash.

**Investigation**:
```bash
# Check MSK cluster status in AWS console
aws kafka describe-cluster --cluster-arn <arn>
# Check broker connectivity from within cluster
kubectl exec -n city-services deploy/kafka-producer -- \
  nc -zv b-1:9098 b-2:9098 b-3:9098
```

**Resolution**: MSK Express auto-recovers. If persistent, check AWS Service Health dashboard. Verify security group rules allow traffic on port 9098.

---

## 3. KafkaUnderReplicatedPartitions

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: Partitions have fewer in-sync replicas than the configured replication factor (3).

**Possible causes**: Broker failure, network partition, disk issues on a broker.

**Resolution**: Monitor MSK console. Usually self-healing. If persistent, contact AWS support.

---

## 4. KafkaOfflinePartitions

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: Partitions have no leader and cannot accept produce/consume requests.

**Resolution**: Immediate AWS support escalation. Data loss risk. Check MSK cluster health.

---

## 5. NodeHighCPUUsage

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: EC2 node CPU > 90% for 10 minutes.

**Investigation**: `kubectl top nodes`, `kubectl describe node <name>`, identify noisy pods.

**Resolution**: Add node taints/affinity to redistribute load, scale node group, optimize pod resource requests.

---

## 6. NodeHighMemoryUsage

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: EC2 node memory > 90% for 10 minutes.

**Resolution**: Same as CPU. Identify memory-leaking pods, increase node size, or add nodes.

---

## 7. NodeDiskFull

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: Node disk usage > 90%. Impacts pod scheduling and node stability.

**Investigation**:
```bash
kubectl debug node/<name> -it --image=busybox -- df -h
kubectl describe node <name> | grep -A5 Allocated
```

**Resolution**: Clean up unused container images, old logs, or resize EBS volumes via Terraform.

---

## 8. PodCrashLooping

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: A pod is crash-looping for > 5 minutes.

**Investigation**: `kubectl logs -n <ns> <pod> --previous`, `kubectl describe pod -n <ns> <pod>`.

**Resolution**: Fix configuration, resource limits, or application bug. Rollback if recent deployment.

---

## 9. PodPending

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: Pod stuck in Pending state for > 10 minutes.

**Investigation**: `kubectl describe pod <pod>` — check Events for insufficient resources, PVC binding failures, or node selector mismatches.

**Resolution**: Add nodes, fix PVC, or correct scheduling constraints.

---

## 10. K8sDeploymentReplicasMismatch

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: Desired replicas != available replicas for > 10 minutes.

**Resolution**: Check deployment events, pod status, resource availability. Rollback if deployment triggered.

---

## 11. K8sJobFailed

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: A Kubernetes Job completed with non-zero exit code.

**Investigation**: `kubectl logs -n <ns> job/<name>`.

**Resolution**: Fix the job logic or input parameters, re-run.

---

## 12. EtcdLeaderChanges

| Field | Value |
|---|---|
| Severity | critical |
| Receiver | PagerDuty |

**What it means**: > 5 etcd leader changes in 10 minutes. Indicates etcd cluster instability.

**Resolution**: Check etcd pod logs, network connectivity between control plane nodes. EKS-managed etcd: contact AWS support.

---

## 13. KafkaConsumerLagWarning

| Field | Value |
|---|---|
| Severity | warning |
| Receiver | Slack |

**What it means**: Kafka consumer lag > 500. Precedes critical threshold.

**Investigation**: Same as KafkaConsumerLagHigh runbook.

**Resolution**: Monitor trend. Scale consumer if lag continues growing.

---

## 14. NodeDiskWarning

| Field | Value |
|---|---|
| Severity | warning |
| Receiver | Slack |

**What it means**: Disk > 80%. Precedes critical.

**Resolution**: Schedule cleanup or volume resize during business hours.

---

## 15. NodeLoadAverageHigh

| Field | Value |
|---|---|
| Severity | warning |
| Receiver | Slack |

**What it means**: System load > 5 for 15 minutes.

**Resolution**: Investigate CPU/memory usage. May be normal under heavy traffic.

---

## 16. PodRestarts

| Field | Value |
|---|---|
| Severity | warning |
| Receiver | Slack |

**What it means**: Pod restarted > 3 times in 1 hour.

**Resolution**: Check logs, resource limits, liveness probe configuration.

---

## 17. K8sDeploymentGenerationMismatch

| Field | Value |
|---|---|
| Severity | warning |
| Receiver | Slack |

**What it means**: Observed generation does not match desired generation.

**Resolution**: Check deployment status. May indicate failed rollout.

---

## 18. LokiDroppedLogs

| Field | Value |
|---|---|
| Severity | warning |
| Receiver | Slack |

**What it means**: > 1% of logs dropped by promtail.

**Resolution**: Check Loki ingest capacity, rate limits, network connectivity. Scale Loki or adjust batch sizes.

---

## 19. PrometheusTargetDown

| Field | Value |
|---|---|
| Severity | warning |
| Receiver | Slack |

**What it means**: > 5% of scrape targets are unreachable.

**Resolution**: Check target status in Prometheus UI (`/targets`). Identify and fix failing ServiceMonitors or endpoint issues.

---

## 20. NodeDiskInfo

| Field | Value |
|---|---|
| Severity | info |
| Receiver | null |

**What it means**: Disk usage > 70%. Informational.

---

## 21. PrometheusNotificationQueue

| Field | Value |
|---|---|
| Severity | info |
| Receiver | null |

**What it means**: Alertmanager notification queue > 50%. Informational.

---

## 22. KafkaRequestRate

| Field | Value |
|---|---|
| Severity | info |
| Receiver | null |

**What it means**: Kafka request rate exceeds 2x baseline. Informational — may indicate traffic surge requiring capacity planning.
