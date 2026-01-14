# coolkit – Operational Runbook

This document describes how to deploy, operate, observe, and scale the **coolkit** internal backend service running on Kubernetes.

The goal is to make day-to-day operations, on-call handling, and scaling behavior clear and predictable.

---

## Service Overview

- **Name:** coolkit
- **Type:** Internal HTTP API
- **Container image:** `gcr.io/example/coolkit:<SHA>`
- **Runtime:** Kubernetes (single cluster per deployment)
- **Ports:**
  - `8080` – main HTTP API
  - `2345` – observability (health + metrics)
- **State:**
  - Distributed in-memory cache **within a single cluster**
  - Persistent storage via **Cloud SQL**

---

## Deployment

### Deployment Method
- Deployed via **Helm**
- Image versions are pinned using **SHA tags**
- Rolling updates are used to minimize cache disruption

### Required Configuration
- `image.tag` **must** be set to a valid SHA
- Database connection settings must be provided via environment variables or envFrom (In a production example we can use Vault or External secrets)

### Test Deployment 
```bash
helm template coolkit ./helm \
  --namespace coolkit \
  --set image.tag=deadbeef \
  --set 'database.env[0].name=DATABASE_URL' \
  --set 'database.env[0].value=postgres://user:pass@127.0.0.1:5432/db'
```

### Example Deployment
```bash
helm upgrade --install coolkit ./coolkit \
  --namespace production \
  --create-namespace \
  --set image.tag=<IMAGE_SHA>
```

### Rollout Strategy

- RollingUpdate
- maxUnavailable: 10%
- maxSurge: 10%

This ensures gradual replacement of pods and avoids large cache invalidations.


## Scaling 

### Scaling Mechanism
- Scaling is handled by KEDA
- KEDA polls an internal metrics API endpoint:
```
http://scaler.production.svc.cluster.local/estimate/coolkit
```

### Replica Limits
- Minimum replicas: 10
- Maximum replicas: 100

### Scaling Characteristics
- Polling interval: 15 seconds
- Cooldown period: 60 seconds
- Designed to handle bursty, high-throughput traffic

Note: The semantics of the scaler response (e.g. desired replicas vs load indicator) should be validated and tuned via targetValue.

## Pod Communication & Cache Topology
- Pods form a distributed in-memory cache
- Cache membership is cluster-local
- Pods discover each other via a headless Service:
```
coolkit-headless.<namespace>.svc.cluster.local
```

### Important Constraints
- Cache is not shared across clusters
- Multi-cluster deployments operate independent cache rings
- Persistent data must be written to Cloud SQL

## Availability & Disruptions
### Pod Disruption Budget
- A PodDisruptionBudget is configured: minAvailable: 80%
- This protects cache stability during:
  - Node upgrades
  - Voluntary disruptions
  - Cluster maintenance
- Scheduling
  - Pods are spread across availability zones using topologySpreadConstraints
- Reduces blast radius of zonal failures

## Health Checks
### Health Endpoint
- GET /healthz
- Served on port 2345
### Usage
- Used for:
  - Kubernetes readiness probes
  - Kubernetes liveness probes
  - Load balancer health checks
### Expected Behavior
- Return success when:
  - Process is running
  - Cache subsystem is healthy
  - Database connectivity is available

## Observability
### Metrics
- GET /metrics
- Served on port 2345

### Key Metrics to Monitor 
- Request rate (RPS)
- Latency (p50 / p95 / p99)
- Error rate (5xx)
- CPU throttling
- Memory utilization
- Cache peer count 
- Database connection errors

### Alerting Recommendations
- High HTTP 5xx rate
- Sustained high latency (p95 / p99)
- Pod crash looping
- Memory near limit
- KEDA scaling not reacting to load
- Sudden drop in replica count
- Cache peer count below expected minimum

## CloudSQL 
Cloud SQL introduces trade-offs compared to classic username/password database access, including IAM-based connection control, connection limits, and reduced portability. These constraints require careful connection pooling and database-level authorization but provide stronger security defaults and simplified credential management.

## Operational Notes
- Validate scaler behavior under load before production ramp-up
- Avoid aggressive rollouts during high traffic
- Ensure node pools can scale to accommodate peak replica counts