# Dead Letter Queue

Processes failed messages from all pipeline topics by classifying failures and taking appropriate action.

## Failure Classification

| Type | Action |
|---|---|
| Schema violation | Alert schema registry team, log details |
| Deserialization error | Alert data engineering, mark as data corruption |
| Transient error | Retry up to 3x, then discard |
| Poison pill | Alert security team, discard |

## Architecture

```
Failed message → DLQ topic (dlq.all) → DLQ Processor → Classification → Handler
```

## Deployment

```bash
kubectl apply -f dlq-configmap.yaml
kubectl apply -f dlq-deployment.yaml
```
