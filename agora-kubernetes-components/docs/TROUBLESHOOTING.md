# Troubleshooting Guide

## Pod Not Starting

### Symptoms
- `kubectl get pods` shows `CrashLoopBackOff`, `ImagePullBackOff`, or `Pending`
- Pod stuck in `Init:0/1` or `ContainerCreating`

### Diagnosis

```bash
# Check pod status and events
kubectl describe pod <pod-name> -n city-services

# Check logs (if container ran at all)
kubectl logs <pod-name> -n city-services

# Check previous instance logs (after crash)
kubectl logs <pod-name> -n city-services --previous
```

### Common Causes

| Issue | Check | Fix |
|-------|-------|-----|
| Liveness probe failing | `kubectl describe pod` shows probe failure | Increase `initialDelaySeconds` or adjust probe path |
| Readiness probe failing | Pod shows `Running` but `0/1 READY` | Check `/ready` endpoint, verify dependencies are up |
| Resource limits exceeded | Pod is `OOMKilled` | Increase memory limits in deployment |
| Image pull error | `ImagePullBackOff` with `ErrImagePull` | Verify image exists in registry and pull secret is correct |
| Container port mismatch | Probe connects to wrong port | Verify `containerPort` matches probe port |
| Startup probe timeout | Pod restarts before probe succeeds | Increase `failureThreshold` for slow-starting services |

## Network Policy Blocking Traffic

### Symptoms
- Service-to-service communication timeout
- `Connection refused` or `Connection timed out`
- curl/wget from one pod to another fails

### Diagnosis

```bash
# Verify network policies exist
kubectl get networkpolicies --all-namespaces

# Check if a specific policy allows the traffic
kubectl describe networkpolicy allow-city-services-internal -n city-services

# Test connectivity from a pod
kubectl exec <pod-name> -n city-services -- curl -v http://target-service:8080/health
```

### Common Causes

| Issue | Check | Fix |
|-------|-------|-----|
| Default deny blocking | Policy exists with `deny-all` but no allow rule | Verify `allow-city-services-internal` is applied |
| Wrong namespace labels | Policy uses `namespaceSelector` but labels don't match | `kubectl get ns --show-labels` to verify |
| Port not in policy | Policy allows to port 8080 but service uses 9090 | Update policy port list |
| Missing egress rule | Pod can receive traffic but cannot send responses | Add egress rule for response traffic |
| Ingress from kube-system | ALB controller can't reach api-gateway | Verify `allow-ingress-controller` is applied |

## HPA Not Scaling

### Symptoms
- Replicas stuck at min, even under load
- HPA shows `<unknown>` for metrics
- Scaling happens too slowly or too fast

### Diagnosis

```bash
# Check HPA status
kubectl describe hpa traffic-optimizer -n city-services

# Check if metrics-server is running
kubectl get pods -n kube-system | grep metrics-server

# Check resource requests are set (HPA requires them)
kubectl get deployment traffic-optimizer -n city-services -o yaml | grep -A5 resources
```

### Common Causes

| Issue | Check | Fix |
|-------|-------|-----|
| Metrics server not running | HPA shows `<unknown>` for metrics | `kubectl top pods` to verify |kubectl top pods -n city-services |
| No resource requests set | HPA cannot calculate utilization | Add `resources.requests.cpu/memory` to container spec |
| Stabilization window delay | HPA is working but waiting | Wait 5 minutes (scale-down stabilization window) |
| Max replicas reached | HPA shows desired = max | Increase `maxReplicas` or investigate why load is so high |
| Custom metrics unavailable | External metrics show `<unknown>` | Verify Prometheus adapter configuration |

## Kafka Connection Issues

### Symptoms
- data-broker logs show connection errors to MSK
- Consumer group not receiving messages
- `Connection refused` or TLS errors

### Diagnosis

```bash
# Check data-broker logs
kubectl logs -l app.kubernetes.io/name=data-broker -n city-services --tail=50

# Verify service account annotation (IRSA)
kubectl describe sa data-broker-sa -n city-services

# Check network policy allows egress to MSK
kubectl describe networkpolicy allow-city-services-internal -n city-services
```

### Common Causes

| Issue | Check | Fix |
|-------|-------|-----|
| IRSA not configured | SA missing annotation | Add `eks.amazonaws.com/role-arn` annotation to data-broker-sa |
| Wrong MSK endpoint | `KAFKA_BOOTSTRAP_SERVERS` env var wrong | Check MSK console for correct broker endpoints |
| Security group blocking | MSK SG doesn't allow from EKS nodes | Add EKS node SG to MSK inbound rule (port 9098) |
| TLS configuration | Missing truststore or wrong protocol | Verify Kafka client TLS settings match MSK config |
| Network policy blocking | Egress to MSK (port 9098) denied | Add egress rule for VPC CIDR:9098 in network policy |
