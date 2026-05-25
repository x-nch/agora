# API Reference — Agora Platform

> **Complete API documentation for the Woven City Agora platform.**
> **Last Updated**: May 2026

*This document is maintained by the docs/api-documenter agent.*

---

## Overview

The Agora platform exposes REST APIs for:

- **Device Telemetry Ingestion** — IoT device data submission
- **City Service Control** — Traffic optimization, energy management control
- **Inventor Data Access** — Anonymized data queries
- **Incident Reporting** — Anomaly detection and alert management
- **Health Monitoring** — Service health probes

---

## API Specification

The complete OpenAPI 3.0 specification is available at:

- **YAML**: [`agora-platform-openapi.yaml`](agora-platform-openapi.yaml)
- **Rendered**: (via Swagger UI / Redoc — see below)

---

## Base URLs

| Environment | Base URL |
|-------------|----------|
| Development | `https://api.dev.agora.woven-city.jp` |
| Staging | `https://api.staging.agora.woven-city.jp` |
| Production | `https://api.agora.woven-city.jp` |

---

## Core API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/traffic/optimize` | POST | Traffic signal optimization request |
| `/api/v1/energy/optimize` | POST | Energy distribution optimization |
| `/api/v1/telemetry` | POST | Device telemetry ingestion |
| `/api/v1/data/anonymized` | GET | Anonymized data for inventors |
| `/api/v1/incidents` | GET, POST | Incident reporting and query |
| `/health/live` | GET | Liveness probe |
| `/health/ready` | GET | Readiness probe |
| `/metrics` | GET | Prometheus metrics |

---

## Authentication

All API requests require authentication via:

- **Internal services**: IAM-based auth via IRSA (no API keys needed)
- **External/inventor services**: API key in `X-API-Key` header
- **Devices**: mTLS certificate authentication

---

## Viewing the API Spec

To render the OpenAPI specification:

```bash
# With Redoc
npx redoc-cli bundle docs/api/agora-platform-openapi.yaml

# With Swagger UI
docker run -p 80:8080 -e SWAGGER_JSON=/openapi.yaml \
  -v $(pwd)/docs/api:/openapi.yaml swaggerapi/swagger-ui
```

---

## Related Documentation

- [Security Architecture](../SECURITY.md) — IAM, API auth, rate limiting
- [Data Broker Architecture](../ARCHITECTURE.md#7-data-pipeline-architecture) — How data flows through the API
- [Health Endpoints](../TROUBLESHOOTING.md#13-health-check-endpoints) — Health check reference
