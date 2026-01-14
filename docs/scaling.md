# Scaling from one cluster to many clusters (ArgoCD-based) 

## Overview
To scale the deployment from a single Kubernetes cluster to multiple clusters, a hub-and-spoke architecture is used.
The service’s distributed in-memory cache is intentionally scoped to a single cluster. When deploying to multiple clusters, each cluster maintains its own cache ring, while Cloud SQL acts as the source of truth. This approach keeps the system simple, low-latency, and fault-isolated, with the known trade-off of cold caches during regional failover. Introducing a globally shared cache would require a deliberate architectural change and increased operational complexity.

## Hub cluster
The hub cluster acts as the management and control plane. It hosts shared internal tooling such as: 
- ArgoCD (GitOps and deployments)
- Grafana, Loki, Tempo, Mimir (centralized observability)
- Vault for secrets management and injection into spoke clusters
This cluster does not run application workloads.

## Spoke cluster
Spoke clusters are responsible for running application workloads. In this example, each spoke cluster runs the coolkit service and maintains its own distributed in-memory cache scoped to that cluster.

## Traffic routing and failover
- A global HTTP load balancer or DNS-based routing is placed in front of all clusters:
    - Traffic is routed to the closest healthy region.
    - Health checks use the /healthz endpoint.
- Failover strategy:
    - If a region becomes unavailable, traffic is routed to the next best region.
    - Cold-cache behavior is expected during failover and is considered acceptable or mitigated through warm-up strategies if required.

## Infrastructure automation and configuration management
Terraform and Terragrunt can be used to provision and manage infrastructure across regions or clouds, ensuring consistency and parity between environments. Environment-specific configuration are injected dynamically and managed through GitOps workflows through the argocd-bridge architecture. Secret management and rotation are handled through Vault.

### ArgoCD ApplicationSet (many clusters)
An ApplicationSet is used to deploy the same Helm chart across multiple clusters:

- A single ArgoCD instance in the hub cluster manages all spoke clusters
- Clusters are labeled (e.g. `region=us`, `environment=prod`)
- The ApplicationSet selects clusters based on labels and applies per-environment or per-cluster overrides

This gives:
- Uniform deployment across regions
- Environment and cluster-specific configuration
- Gradual and controlled rollouts

Example:
```
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: workload-coolkit
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            enable_coolkit: "true"
  template:
    metadata:
      name: coolkit-{{name}}
    spec:
      project: default
      source:
        chart: coolkit
        repoURL: https://gcr.io/example/coolkit
        targetRevision: 1.0.0
        helm:
          valueFiles:
            - values.yaml
      destination:
        name: '{{name}}'
        namespace: coolkit
      syncPolicy:
        automated: {}
```
Dynamic cluster metadata (e.g. region, cluster name, VPC) can be injected to reduce configuration duplication while still allowing per-environment and per-cluster overrides when necessary. 

### Networking
Inter-cluster networking is intentionally kept simple, as the service does not require cross-cluster pod communication. More advanced networking solutions (e.g. Cilium, multi-cluster service meshes) can be evaluated if cross-cluster communication becomes a future requirement.

### Progressive delivery 
- Argo Image Updater can be used to detect new SHA-based image tags
- Argo Rollouts can be used per cluster to perform canary deployments:
    - 5% → 25% → 50% → 100% with automated metric checks (p95 latency, 5xx).
- Region-by-region promotion can be orchestrated using ArgoCD sync waves

### Multi-cluster observability
- Standardize labels: `cluster`, `region`, `env`, `app`.
- Centralize metrics/logs:
    - Metrics via Prometheus remote-write to Mimir
    - Logs via Loki.
    - Traces via Tempo
- Dashboards per region + global aggregate view.