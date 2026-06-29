# Omnia Telemetry Helm Chart

Unified Helm chart for deploying the Dell Omnia telemetry stack on Kubernetes.
A single `helm install` brings up the complete pipeline: hardware and infrastructure
sources, Kafka-based message routing, Vector transformation bridges, and
VictoriaMetrics/VictoriaLogs storage.

## Architecture

```
SOURCES                    BRIDGES                    SINKS
+-----------+          +-------------+          +-------------------+
| iDRAC     |--+------>| Kafka       |--------->| VictoriaMetrics   |
| LDMS      |  |       | (Strimzi)   |          | (Operator-managed)|
| DCGM      |  |       +------+------+          +-------------------+
+-----------+  |              |                  +-------------------+
               |       +------v------+          | VictoriaLogs      |
+-----------+  |       | Vector-LDMS |--------->| (Operator-managed)|
| PowerScale|--+       | Vector-OME  |          +-------------------+
| UFM       |  |       +-------------+
| VAST      |--+
| OME       |
+-----------+

HEALTH MANAGEMENT
+---------------------------+
| Telemetry Health Operator |  <-- replaces CronJob pod-cleanup
| (CRD: TelemetryHealth    |
|  Policy / Status)         |
+---------------------------+
```

## Prerequisites

| Dependency | Version | Purpose |
|------------|---------|---------|
| Kubernetes | >= 1.27 | Target cluster |
| Helm | >= 3.12 | Chart installation |
| Strimzi Operator | >= 0.48 | Manages Kafka CRs |
| VictoriaMetrics Operator | >= 0.59 | Manages VM/VL CRs |

The Strimzi and VictoriaMetrics operators must be installed separately before
deploying this chart. The chart creates CRs (Kafka, VMCluster, VLCluster, etc.)
that these operators reconcile.

## Quick Start

```bash
# Install with defaults (all components enabled)
helm install telemetry ./omnia-telemetry -n telemetry --create-namespace

# Install with minimal sources (only iDRAC + Kafka + VictoriaMetrics)
helm install telemetry ./omnia-telemetry -n telemetry --create-namespace \
  --set ldms.enabled=false \
  --set vector.enabled=false \
  --set external-sources.enabled=false \
  --set telemetry-operator.enabled=false

# Install with custom values file
helm install telemetry ./omnia-telemetry -n telemetry --create-namespace \
  -f my-values.yaml
```

## Upgrade

```bash
helm upgrade telemetry ./omnia-telemetry -n telemetry -f my-values.yaml
```

## Uninstall

```bash
helm uninstall telemetry -n telemetry

# Optionally clean up PVCs (DATA LOSS)
# kubectl delete pvc -n telemetry --all
```

## Chart Structure

```
omnia-telemetry/
  Chart.yaml                       # Umbrella chart metadata
  values.yaml                      # Unified configuration surface
  README.md                        # This file
  templates/
    _helpers.tpl                   # Shared template helpers
    namespace.yaml                 # Namespace (pre-install hook)
    tls-cert-job.yaml              # Self-signed TLS cert generation (hook)
    NOTES.txt                      # Post-install instructions
  charts/
    kafka/                         # Strimzi Kafka (KRaft mode)
      templates/
        kafka-cluster.yaml         # KafkaNodePool + Kafka CRs
        kafka-bridge.yaml          # KafkaBridge + LB Service
        kafka-topics.yaml          # KafkaTopic CRs (idrac, ldms)
        kafka-users.yaml           # KafkaUser (kafkapump)
    victoria-metrics/              # VictoriaMetrics + VictoriaLogs
      templates/
        vmcluster.yaml             # VMCluster or VMSingle CR
        vmagent.yaml               # VMAgent CR
        vmagent-rbac.yaml          # ServiceAccount, Role, ClusterRole
        vmscrape.yaml              # VMPodScrape (iDRAC)
        vlcluster.yaml             # VLCluster CR
        vlagent.yaml               # VLAgent CR (syslog receiver)
        vlagent-config.yaml        # VLAgent pipeline ConfigMap
    idrac/                         # iDRAC Telemetry
      templates/
        statefulset.yaml           # Multi-container StatefulSet
        service.yaml               # Headless Service
        secret.yaml                # MySQL credentials
    ldms/                          # LDMS aggregator + store
      templates/
        statefulset-agg.yaml       # Aggregator StatefulSet
        statefulset-store.yaml     # Store StatefulSet (Kafka writer)
        secrets.yaml               # OVIS auth + Munge key
    vector/                        # Vector bridges
      templates/
        vector-ldms-*.yaml         # LDMS Kafka-to-VM pipeline
        vector-ome-*.yaml          # OME Kafka-to-VM/VL pipeline
        vector-ome-kafkauser.yaml  # Dedicated KafkaUser for OME
        vmagent-vector-*.yaml      # Metrics write-buffer
        vlagent-vector-*.yaml      # Logs write-buffer
    external-sources/              # UFM, VAST, PowerScale
      templates/
        ufm-*.yaml                 # External Service + Secret + VMScrape
        vast-*.yaml                # External Service + Secret + VMScrape
        powerscale-csi-exporter.*  # CSI Volume Exporter Deployment
    telemetry-operator/            # Health operator
      crds/
        telemetryhealthpolicy.yaml # CRD: health rules + remediation
        telemetryhealthstatus.yaml # CRD: cluster health summary
      templates/
        operator-deployment.yaml   # Controller Deployment
        operator-rbac.yaml         # RBAC (SA, ClusterRole, CRB)
        default-health-policy.yaml # Default remediation rules
```

## Configuration

All configuration is done through `values.yaml`. The top-level structure:

| Section | Purpose |
|---------|---------|
| `global.*` | Namespace, image registry override, pull secrets |
| `tls.*` | TLS certificate management (self-signed or existing) |
| `sources.*` | Enable/disable telemetry sources and their targets |
| `bridges.*` | Enable/disable Vector bridge pipelines |
| `kafka.*` | Kafka cluster sizing, storage, topics, bridge |
| `victoria-metrics.*` | VM/VL cluster sizing, retention, scrape configs |
| `idrac.*` | iDRAC StatefulSet images, resources, collection targets |
| `ldms.*` | LDMS aggregator/store config, sampler plugins |
| `vector.*` | Vector LDMS/OME bridge config, write-buffers |
| `external-sources.*` | UFM, VAST, PowerScale endpoints and auth |
| `telemetry-operator.*` | Health operator config, default remediation policy |

### Key Configuration Examples

#### Air-Gapped Deployment

```yaml
global:
  imageRegistry: "registry.internal:5000"
```

All images are automatically prefixed with the registry override.

#### Disable Components

```yaml
ldms:
  enabled: false
vector:
  ldms:
    enabled: false
external-sources:
  ufm:
    enabled: false
  vast:
    enabled: false
```

#### Custom Retention and Storage

```yaml
victoria-metrics:
  metrics:
    retention: "720h"           # 30 days
    persistenceSize: "50Gi"
  logs:
    retention: "336h"           # 14 days
    storageSize: "20Gi"
kafka:
  cluster:
    storage:
      size: "20Gi"
    config:
      logRetentionHours: 336
```

#### External UFM/VAST Sources

```yaml
external-sources:
  ufm:
    enabled: true
    endpoint: "10.10.10.50"
    port: 9001
    credentials:
      username: "admin"
      password: "changeme"
  vast:
    enabled: true
    endpoint: "10.10.10.60"
    port: 443
    credentials:
      username: "admin"
      password: "changeme"
```

#### Use Existing TLS Certificates

```yaml
tls:
  enabled: true
  selfSigned:
    enabled: false
  existingSecret: "my-tls-secret"   # Must contain tls.crt, tls.key, ca.crt
```

#### Single-Node VictoriaMetrics (small clusters)

```yaml
victoria-metrics:
  metrics:
    deploymentMode: single
```

## Helm Tests

Each sub-chart includes Helm test pods:

```bash
helm test telemetry -n telemetry
```

| Test | Validates |
|------|-----------|
| `kafka-test` | Kafka bootstrap connectivity |
| `vm-write-test` | VictoriaMetrics write endpoint |
| `idrac-mysql-test` | MySQL connectivity |
| `ldms-agg-test` | LDMS aggregator port |
| `vector-test` | Vector bridge health endpoints |
| `external-sources-test` | CSI exporter health |
| `operator-test` | Operator metrics endpoint |

## Data Flow

```
iDRAC hardware
  --> idrac-telemetry-receiver (SSE/Redfish)
    --> ActiveMQ (in-pod message bus)
      --> kafkapump --> Kafka topic "idrac"
      --> victoriapump --> VMAgent scrape (port 2112)

LDMS samplers (compute nodes)
  --> ldms-aggregator (TCP:6001)
    --> ldms-store --> Kafka topic "ldms"
      --> vector-ldms --> vmagent-vector --> vminsert --> VictoriaMetrics

OME appliance
  --> Kafka topics "ome.*"
    --> vector-ome
      --> metrics: vmagent-vector --> vminsert --> VictoriaMetrics
      --> logs:    vlagent-vector --> vlinsert --> VictoriaLogs

PowerScale
  --> syslog UDP/TCP:514 --> VLAgent --> vlinsert --> VictoriaLogs
  --> OTEL Collector --> VMAgent scrape --> VictoriaMetrics

UFM / VAST
  --> External Service (headless) --> VMServiceScrape --> VMAgent --> VictoriaMetrics
```

## Health Operator

The Telemetry Health Operator replaces the legacy CronJob-based pod cleanup.
It watches pods in the telemetry namespace and applies graduated remediation:

| Condition | Threshold | Actions |
|-----------|-----------|---------|
| Stuck terminating (general) | 60s | RemoveFinalizers, ForceDelete, CleanPvcLockFiles |
| Stuck terminating (Kafka) | 300s | RemoveFinalizers, ForceDelete |
| CrashLoopBackOff | 5 restarts | Alert (warning) |
| Pending too long | 300s | Alert (warning) |

Custom policies can be created by deploying additional `TelemetryHealthPolicy` CRs.

## License

Copyright 2025 Dell Inc. or its subsidiaries. All Rights Reserved.
Licensed under the Apache License, Version 2.0.
