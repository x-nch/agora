# Schema Registry

Deploys Confluent Schema Registry on EKS for AVRO schema management across all pipeline topics.

## Configuration

- **Default compatibility**: BACKWARD
- **Incidents topic**: FORWARD_TRANSITIVE (schema evolves frequently)
- **Signal commands**: BACKWARD (safety-critical, strict)
- **Auth**: MSK IAM (IRSA via service account)

## Deployment

```bash
kubectl apply -f schema-registry-configmap.yaml
kubectl apply -f schema-registry-deployment.yaml
kubectl apply -f schema-registry-service.yaml
kubectl apply -f schema-registry-pdb.yaml
kubectl apply -f schema-registry-hpa.yaml
```

## Topic-Level Compatibility Override

```bash
# Set incidents topic to FORWARD_TRANSITIVE
curl -X PUT http://schema-registry:8081/config/agora.incidents.Incident \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"compatibility": "FORWARD_TRANSITIVE"}'
```
