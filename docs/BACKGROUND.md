# Background — Woven City & The Agora Platform

> **Context, vision, and problem statement for the Woven City Agora infrastructure project**
> **Last Updated**: May 2026

---

## Table of Contents

1. [What is Woven City?](#1-what-is-woven-city)
2. [What is Agora?](#2-what-is-agora)
3. [Why This Matters](#3-why-this-matters)
4. [The Technical Problem](#4-the-technical-problem)
5. [Key Requirements](#5-key-requirements)
6. [Woven City April 2026 Announcements](#6-woven-city-april-2026-announcements)
7. [Related Systems: Arene vs Agora](#7-related-systems-arene-vs-agora)
8. [Project Goals](#8-project-goals)

---

## 1. What is Woven City?

**Woven City** is a 175-acre smart city prototype at the base of Mount Fuji in Susono City, Shizuoka Prefecture, Japan. It is Toyota's living laboratory for future mobility, smart infrastructure, and human-centric urban design.

### Status (May 2026)

| Fact | Detail |
|------|--------|
| Launch date | September 2025 |
| Phase 1 residents | ~360 (Toyota/Woven employees and families, "Weavers") |
| Target capacity | 2,000+ across future phases |
| Active inventor projects | 20+ (including UCC Japan — AI-powered retail) |
| Accelerator program | Woven City Challenge (global startup open call) |
| CTO | John Absmeier |
| Total investment | ~$10 billion (unconfirmed by Toyota) |
| General visitor program | Planned for FY2026 onward |

### Physical Layout — 5 Districts

| District | Purpose | Key Infrastructure |
|----------|---------|-------------------|
| **Mobility** | Autonomous vehicle testing, V2X | Traffic signals, road sensors, charging stations |
| **Living** | Smart homes, IoT daily life | Building management, energy monitoring |
| **Working** | Offices, research labs, innovation | Collaborative workspaces, 5G connectivity |
| **Wellness** | Healthcare, fitness | Health sensors, environmental monitoring |
| **Innovation** | Inventor Garage, third-party labs | Partner sandbox environment |

The city is fully connected with thousands of IoT devices:
- Traffic signals (smart, data-driven timing)
- Environmental sensors (temperature, air quality, humidity, PM2.5, CO2, NOx)
- Vehicle sensors (autonomous cars, connected mobility)
- Building management systems (HVAC, lighting, energy consumption)
- Road infrastructure (pavement stress, pothole detection, water level)
- Safety systems (emergency beacons, camera networks, ANZEN system)

---

## 2. What is Agora?

**Agora** (also called the "City Platform") is **the central nervous system of Woven City**. It is the infrastructure layer that orchestrates all digitally connected city services.

> **Crucial distinction**: Agora is NOT a consumer app. It is the underlying platform that enables all city services to function — from traffic optimisation to energy management to the external inventor ecosystem.

### Core Functions

#### 2.1 Real-Time Data Ingestion

Every device in the city sends data continuously:
- **Vehicles**: GPS, speed, acceleration, brake pressure, wheel sensors (10Hz per vehicle)
- **Traffic signals**: Queue length, pedestrian crossings, incident reports, wait times
- **Buildings**: Temperature, occupancy, energy consumption, HVAC status
- **Roads**: Surface condition, water level, structural stress
- **Environmental**: Air quality (PM2.5, CO2, NOx), temperature, humidity

**Scale**: ~60,000 real-time data points per second from 10,000+ devices.

#### 2.2 Real-Time Optimization

Agora processes data in real-time to make city-wide decisions:

**Traffic Optimization:**
```
Signal detects queue_length=42
  → sends to Agora (< 50ms)
  → traffic optimizer checks nearby signals, vehicle flow
  → sends command: "extend green 10 seconds" (< 100ms total)
  → result: 20% average wait time reduction
```

**Energy Optimization:**
```
Weather forecast predicts 5°C drop
  → energy optimizer cross-references occupancy, consumption
  → reduces HVAC pre-cooling, shifts to off-peak
  → result: 15% energy savings, no occupant discomfort
```

**Autonomous Vehicle Coordination:**
```
Vehicle A requests intersection crossing
  → Agora checks signal state, Vehicle B trajectory, pedestrians
  → confirms safe crossing within 50ms
  → result: collision-free, smooth traffic flow
```

#### 2.3 Data Brokering & Privacy

Agora controls **who gets what data** — the privacy layer that makes multi-tenancy safe:

```
Raw data: Vehicle X (ID: 12345) at (35.123, 140.456) moving 45 km/h
  → For city services: "Highway A averaging 42 km/h" (aggregated)
  → For inventor traffic app: "Your ETA: 12 minutes ±2" (anonymized)
  → Never: individual vehicle IDs, driver identities, exact routes
```

#### 2.4 Microservices Orchestration

100+ internal services coordinate on Agora:
- Traffic optimization (30+) | Energy management (15+)
- Payment systems (20+) | Mobility coordination (25+)
- Safety & emergency (10+) | Wellness & lifestyle (5+)

#### 2.5 External Inventor Ecosystem

External developers build on Agora (like an app store):
- Traffic prediction apps
- Energy management startups
- Wellness services
- Retail optimization

With constraints: authorized data only, no individual identification, rate-limited, monitored for fairness.

---

## 3. Why This Matters

### For Toyota

| Motivation | Detail |
|------------|--------|
| **Real-world testbed** | Autonomous vehicles, smart infrastructure, future mobility |
| **Live laboratory** | How people interact with smart cities at scale |
| **Proof of concept** | Toyota's mobility vision — entire city orchestration |
| **Investor confidence** | Smart city execution beyond vehicle software |

### For the Industry

Woven City is the world's most ambitious smart city project. Success or failure will define:
- How autonomous vehicles integrate with city infrastructure
- Whether multi-tenant data platforms can handle both city operations and external innovation
- The viable scale and cost of smart city technology
- Whether privacy-preserving data brokering works at city scale

---

## 4. The Technical Problem

### Scale Constraints

| Metric | Requirement |
|--------|-------------|
| Concurrent devices | 10,000+ |
| Event throughput | 60,000+ msg/sec |
| Event size | ~1 KB average |
| Throughput | ~60 MBps |
| End-to-end latency (traffic) | < 100ms P99 |
| End-to-end latency (energy) | < 1s P99 |
| Anomaly detection | < 500ms |
| Data retention (raw) | 7 days (Kafka) → S3 archive |
| Data retention (alerts) | 90 days |
| Multi-tenancy | Internal + external, isolated |
| Availability | 99.95% |
| Recovery | RPO 5 min, RTO 15 min |

### Architecture Challenges

1. **High-throughput, low-latency event streaming**: 60K msg/sec at <100ms end-to-end with no data loss
2. **Multi-tenant isolation**: Internal city services (privileged) and external inventors (restricted) sharing the same infrastructure
3. **Privacy-preserving data brokering**: Strip PII, aggregate locations, enforce per-inventor access policies — in real-time
4. **Cost-efficient scaling**: Pay-per-use for dev, reserved capacity for prod; every layer scales independently
5. **Security at scale**: Encryption everywhere, IAM auth for Kafka (no passwords), IRSA for pod-level permissions
6. **Disaster recovery**: Multi-AZ tolerance, automated failover, S3 archival with replay capability

---

## 5. Key Requirements

### Functional Requirements

| ID | Requirement |
|----|-------------|
| F1 | Ingest real-time telemetry from 10,000+ devices across 5 city districts |
| F2 | Process and optimise traffic signals with <100ms end-to-end latency |
| F3 | Detect and alert on anomalies (unusual driving, sensor failure) within 500ms |
| F4 | Optimise building energy consumption across the city |
| F5 | Anonymize and broker data between internal services and external inventors |
| F6 | Archive all raw data to durable storage (S3 data lake) |
| F7 | Support schema evolution for all event types |
| F8 | Handle failed messages without data loss (dead letter queue) |

### Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NF1 | 99.95% availability for critical services |
| NF2 | RPO ≤ 5 minutes, RTO ≤ 15 minutes |
| NF3 | 3-AZ redundancy for all critical components |
| NF4 | Encryption at rest and in transit for all data |
| NF5 | Multi-tenancy with network, compute, and data isolation |
| NF6 | Least-privilege IAM — each service has only the permissions it needs |
| NF7 | Environment parity: dev/staging/prod with environment-specific scaling |
| NF8 | Cost-effective: dev uses serverless/pay-per-use, prod uses reserved capacity |

---

## 6. Woven City April 2026 Announcements

In April 2026, Woven by Toyota announced several technologies that directly relate to Agora's infrastructure:

### AI Vision Engine

A large-scale Vision Language Model (VLM) that ingests camera and sensor data city-wide. Combines visual, behavioral, and environmental data to understand and respond to real-world conditions in real-time. Ranks among the world's leading VLMs.

**Infrastructure implications**: The AI Vision Engine will consume processed data from Agora's data pipeline (S3 data lake, stream processors) and produce inference results that flow back through Agora's event streams.

### Integrated ANZEN System

Combines AI Vision Engine with:
- **Behavior AI** — interprets and predicts human behavioral patterns
- **Drive Sync Assist** — driving assistance based on driver needs and surrounding conditions
- Camera data from vehicles + traffic signals enables people, vehicles, and infrastructure as a single coordinated system

**Infrastructure implications**: ANZEN requires the strictest latency SLOs (<50ms for safety-critical paths) and 100% data durability.

### Infra Hub

Integrated data platform that unifies data across the city — the layer that our Terraform infrastructure directly enables.

### Data Fabric

A data management framework for data utilisation while respecting individual privacy — directly informs multi-tenancy and data isolation architecture (Phase 2, Phase 3).

---

## 7. Related Systems: Arene vs Agora

A common point of confusion. Both are Woven by Toyota platforms, but they serve different purposes:

| Dimension | Arene | Agora |
|-----------|-------|-------|
| **Purpose** | Vehicle software platform | City orchestration platform |
| **Domain** | In-vehicle: infotainment, ADAS, SDV | City-wide: device pipelines, multi-tenancy, data brokering |
| **Launched on** | 2026 Toyota RAV4 | Woven City (Sep 2025) |
| **Build stack** | C++, Bazel, safety-certified | AWS, Terraform, K8s, Kafka, Python |
| **Scope** | Per-vehicle software | City-wide infrastructure |
| **Integration** | Sends vehicle data to Agora via Kafka | Processes city data, sends commands to vehicles |

> **Interview tip**: If asked about Arene vs Agora, explain clearly that they are complementary but independent. Arene handles what happens inside the vehicle; Agora handles what happens across the city. The two integrate at the data layer (Kafka topics) but are architecturally separate.

---

## 8. Project Goals

### What This Infrastructure Project Delivers

1. **Complete, production-ready Terraform IaC** (Phase 1)
   - 7 modular, versioned child modules (VPC, EKS, MSK, RDS, S3, Monitoring, IAM)
   - 3 environments (dev/staging/prod) with environment-specific variables
   - Remote state management with S3 + DynamoDB locking
   - All security best practices built-in

2. **Kubernetes multi-tenancy framework** (Phase 2)
   - Namespace isolation, RBAC, network policies, resource quotas
   - 4 core microservices with health checks, autoscaling, PDBs
   - Prometheus + Grafana monitoring
   - Kustomize overlays for environment-specific config

3. **Real-time data pipeline** (Phase 3)
   - 8 Kafka topics with AVRO schemas and strategic partitioning
   - 4 stream processors with consumer-lag-based autoscaling
   - Kafka Connect S3 sink connectors
   - Schema Registry, Dead Letter Queue, IAM auth

### What Makes This Different

| Typical IaC Project | This Project |
|---------------------|--------------|
| Single environment | Dev/staging/prod with meaningful differences |
| Flat structure | 7 versioned child modules, root composition |
| Basic security | KMS, VPC endpoints, IRSA, least-privilege IAM throughout |
| Manual scaling | Multi-layer autoscaling (MSK + Karpenter + HPA + Aurora) |
| No multi-tenancy | Namespace isolation, network policies, quotas, data broker |
| No data pipeline | End-to-end streaming: devices → MSK → processors → S3 |
| No DR plan | RPO/RTO targets, runbooks, cross-region architecture |
