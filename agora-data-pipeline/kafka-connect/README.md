# Kafka Connect

Distributed Kafka Connect cluster for S3 archival of all pipeline topics.

## Architecture

- 2+ worker pods (HPA up to 6)
- IAM auth via IRSA for MSK
- Schema Registry integration for AVRO
- S3 VPC endpoint for data transfer

## Deployment

```bash
kubectl apply -f connect-configmap.yaml
kubectl apply -f connect-deployment.yaml
kubectl apply -f connect-service.yaml
kubectl apply -f connect-pdb.yaml
kubectl apply -f connect-hpa.yaml
```

## S3 Connector Plugin

Add the S3 Sink connector plugin on the container image:

```dockerfile
FROM confluentinc/cp-kafka-connect:7.6.0
RUN confluent-hub install confluentinc/kafka-connect-s3:latest --no-prompt
```

Then rebuild and push the image, updating the deployment image reference.
