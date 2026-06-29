# Component Spec - Omnia Telemetry Helm Chart Redesign

**Version**: 1.0.0-draft
**Date**: 2026-06-26
**Parent**: [Engineering Spec (HLD)](./01-Engineering-Spec-HLD.md)

---

## 1. Umbrella Chart (`omnia-telemetry`)

### 1.1 Chart.yaml

```yaml
apiVersion: v2
name: omnia-telemetry
description: >-
  Dell Omnia Telemetry Stack - unified Helm deployment for hardware and
  infrastructure telemetry collection, routing, and storage.
type: application
version: 1.0.0
appVersion: "1.0.0"
keywords:
  - telemetry
  - monitoring
  - metrics
  - logs
  - victoria-metrics
  - kafka
  - idrac
  - ldms
maintainers:
  - name: Dell Omnia Team

dependencies:
  - name: strimzi-kafka-operator
    version: "0.48.x"
    repository: "https://strimzi.io/charts/"
    condition: kafka.operatorManaged
    alias: strimzi

  - name: victoria-metrics-operator
    version: "0.59.x"
    repository: "https://victoriametrics.github.io/helm-charts/"
    condition: victoria-metrics.operatorManaged
    alias: vmoperator
```

### 1.2 Top-Level Templates

| Template | Purpose | Hook |
|----------|---------|------|
| `namespace.yaml` | Create telemetry namespace | `pre-install`, weight -10 |
| `tls-scripts-configmap.yaml` | ConfigMap with TLS generation script | `pre-install`, weight -9 |
| `tls-cert-job.yaml` | Job to generate self-signed TLS certs | `pre-install`, weight -8 |
| `wait-for-crds.yaml` | Job to wait for operator CRDs | `post-install`, weight -5 |
| `NOTES.txt` | Post-install connection instructions | - |
| `_helpers.tpl` | Shared template functions | - |

### 1.3 Key Helper Functions (`_helpers.tpl`)

```
omnia-telemetry.fullname          # Release-qualified name
omnia-telemetry.namespace         # Target namespace (default: telemetry)
omnia-telemetry.kafkaRequired     # Derived: is Kafka needed?
omnia-telemetry.victoriaMetricsRequired  # Derived: is VM needed?
omnia-telemetry.victoriaLogsRequired     # Derived: is VL needed?
omnia-telemetry.tlsSANs           # Dynamic SAN list for TLS cert
omnia-telemetry.imageRef          # Build image reference with registry override
omnia-telemetry.labels            # Standard Kubernetes labels
omnia-telemetry.selectorLabels    # Pod selector labels
```

---

## 2. Kafka Sub-Chart (`charts/kafka/`)

### 2.1 Overview

Deploys a Strimzi-managed Kafka cluster in KRaft mode (no ZooKeeper) with mTLS,
KafkaBridge for HTTP access, and dynamically created topics/users.

### 2.2 values.yaml Schema

```yaml
# charts/kafka/values.yaml
enabled: true
operatorManaged: true                  # Install Strimzi operator as dependency

cluster:
  version: "4.1.0"
  metadataVersion: "4.1-IV0"
  replicas:
    controllers: 3
    brokers: 3
  listeners:
    internal:
      port: 9092
      tls: true
      auth: none
    tls:
      port: 9093
      tls: true
      auth: tls                        # mTLS
    external:
      enabled: true
      port: 9094
      type: loadbalancer
      tls: true
      auth: tls
  authorization:
    type: simple                       # ACL-based
  storage:
    size: "8Gi"                        # Per-pod PVC size
    storageClass: ""
  config:
    logRetentionHours: 168
    logRetentionBytes: -1
    logSegmentBytes: 1073741824
    minInsyncReplicas: 2
    defaultReplicationFactor: 3
  resources:
    requests:
      memory: "512Mi"
      cpu: "200m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

bridge:
  enabled: true
  image: "quay.io/strimzi/kafka-bridge:0.33.1"
  replicas: 1
  port: 8080
  tls: true
  service:
    type: LoadBalancer

topics:
  # Dynamically created based on enabled sources
  - name: idrac
    enabled: "{{ and .Values.global.sources.idrac.enabled (has \"kafka\" .Values.global.sources.idrac.collectionTargets) }}"
    partitions: 1
    replicas: 2
    config:
      retentionMs: "604800000"         # 7 days
  - name: ldms
    enabled: "{{ and .Values.global.sources.ldms.enabled (has \"kafka\" .Values.global.sources.ldms.collectionTargets) }}"
    partitions: 2
    replicas: 2
    config:
      retentionMs: "604800000"

users:
  kafkapump:
    authentication:
      type: tls
    authorization:
      type: simple
      acls:
        - resource:
            type: topic
            name: idrac
          operations: [Read, Write, Describe]
        - resource:
            type: topic
            name: ldms
          operations: [Read, Write, Describe]
        - resource:
            type: group
            name: "*"
          operations: [Read]

  vectorOme:
    enabled: "{{ or .Values.global.bridges.vectorOme.metricsEnabled .Values.global.bridges.vectorOme.logsEnabled }}"
    authentication:
      type: tls
    authorization:
      type: simple
      acls:
        - resource:
            type: topic
            name: "ome"
            patternType: prefix
          operations: [Read, Describe]
        - resource:
            type: group
            name: "vector-ome"
            patternType: prefix
          operations: [Read]

images:
  operator: "quay.io/strimzi/operator:0.48.0"
  kafka: "quay.io/strimzi/kafka:0.48.0-kafka-4.1.0"
  bridge: "quay.io/strimzi/kafka-bridge:0.33.1"

entityOperator:
  userOperator:
    resources:
      requests:
        memory: "512Mi"
        cpu: "200m"
      limits:
        memory: "512Mi"
        cpu: "1000m"
```

### 2.3 Template Files

| Template | K8s Resource | Condition |
|----------|-------------|-----------|
| `kafka-cluster.yaml` | Kafka + KafkaNodePool (controller, broker) | `enabled` |
| `kafka-bridge.yaml` | KafkaBridge + Service(LB) | `enabled && bridge.enabled` |
| `kafka-topics.yaml` | KafkaTopic (loop over `topics`) | per-topic `enabled` |
| `kafka-users.yaml` | KafkaUser (kafkapump, vectorOme) | per-user `enabled` |
| `_helpers.tpl` | Template helpers | - |

### 2.4 Migration from Current

| Current File | New Template | Changes |
|-------------|-------------|---------|
| `kafka.kafka.yaml.j2` | `kafka-cluster.yaml` | Jinja2 -> Go templates; values from `values.yaml` |
| `kafka.kafka_bridge.yaml.j2` + `kafka.kafka_bridge_lb.yaml.j2` | `kafka-bridge.yaml` | Merged into single template |
| `kafka.topic.yaml.j2` | `kafka-topics.yaml` | Loop-based; one template for all topics |
| `kafka.kafkapump_user.yaml.j2` | `kafka-users.yaml` | Combined with vector-ome user |

---

## 3. VictoriaMetrics Sub-Chart (`charts/victoria-metrics/`)

### 3.1 Overview

Deploys VictoriaMetrics (metrics TSDB) and VictoriaLogs (log storage) using
the VictoriaMetrics Operator CRDs. Supports both cluster and single-node modes.

### 3.2 values.yaml Schema

```yaml
# charts/victoria-metrics/values.yaml
enabled: true
operatorManaged: true

# ============================================================================
# METRICS (VictoriaMetrics)
# ============================================================================
metrics:
  enabled: true
  deploymentMode: cluster              # cluster | single

  retention: "168h"                    # 7 days default
  persistenceSize: "8Gi"

  tls:
    enabled: true
    secretName: "victoria-tls-certs"   # Shared from umbrella chart

  cluster:
    vmstorage:
      replicas: 3
      replicationFactor: 2
      dedupMinScrapeInterval: "1m"
      image: "victoriametrics/vmstorage:v1.128.0-cluster"
      resources:
        requests: { memory: "1Gi", cpu: "250m" }
        limits: { memory: "2Gi", cpu: "1000m" }
      terminationGracePeriod: 120
      startupProbe:
        initialDelaySeconds: 30
        periodSeconds: 10
        failureThreshold: 30
        timeoutSeconds: 5
      readinessProbe:
        initialDelaySeconds: 15
        periodSeconds: 5
        failureThreshold: 10
        timeoutSeconds: 5
      tolerationSeconds: 5

    vminsert:
      replicas: 2
      image: "victoriametrics/vminsert:v1.128.0-cluster"
      externalAccess: true             # LoadBalancer service
      resources:
        requests: { memory: "256Mi", cpu: "100m" }
        limits: { memory: "512Mi", cpu: "500m" }

    vmselect:
      replicas: 2
      image: "victoriametrics/vmselect:v1.128.0-cluster"
      maxQueryDuration: "5m"
      maxConcurrentRequests: 8
      cacheDataPath: true
      resources:
        requests: { memory: "256Mi", cpu: "100m" }
        limits: { memory: "512Mi", cpu: "500m" }

  single:
    replicas: 2
    image: "victoriametrics/victoria-metrics:v1.128.0"
    port: 8443

  vmagent:
    replicas: 2
    image: "victoriametrics/vmagent:v1.128.0"
    maxScrapeSize: "16MB"
    promscrapeStreamParse: true
    resources:
      requests: { memory: "128Mi", cpu: "50m" }
      limits: { memory: "512Mi", cpu: "250m" }

  additionalRemoteWriteEndpoints: []
  # - url: https://external:8480/insert/0/prometheus/api/v1/write
  #   tlsInsecureSkipVerify: false

  scrape:
    # VMPodScrape / VMServiceScrape configurations
    idrac:
      enabled: true                    # Linked to sources.idrac.enabled
      port: 2112
      path: /metrics
      interval: "30s"
    powerscaleOtel:
      enabled: true
      port: 8889
      path: /metrics
      interval: "30s"
    csiVolumeExporter:
      enabled: true
      port: 8080
      path: /metrics
      interval: "30s"
    ufm:
      enabled: false
      endpoint: ""
      port: 9001
      interval: "30s"
      timeout: "15s"
      tlsMode: "self_signed"
      authMode: "basic"
    vast:
      enabled: false
      endpoint: ""
      port: 443
      metricsPath: "/api/prometheusmetrics/all"
      interval: "30s"
      timeout: "15s"
      tlsMode: "self_signed"
      authMode: "basic"

# ============================================================================
# LOGS (VictoriaLogs)
# ============================================================================
logs:
  enabled: true

  retention: "168h"
  storageSize: "8Gi"

  tls:
    enabled: true
    secretName: "victoria-tls-certs"

  cluster:
    vlstorage:
      replicas: 3
      replicationFactor: 2
      image: "victoriametrics/victoria-logs:v1.49.0"
      resources:
        requests: { memory: "512Mi", cpu: "100m" }
        limits: { memory: "1Gi", cpu: "500m" }
      terminationGracePeriod: 120

    vlinsert:
      replicas: 2
      image: "victoriametrics/victoria-logs:v1.49.0"
      externalAccess: true
      port: 9481
      resources:
        requests: { memory: "256Mi", cpu: "100m" }
        limits: { memory: "512Mi", cpu: "500m" }

    vlselect:
      replicas: 2
      image: "victoriametrics/victoria-logs:v1.49.0"
      port: 9471
      resources:
        requests: { memory: "256Mi", cpu: "100m" }
        limits: { memory: "512Mi", cpu: "500m" }

  vlagent:
    replicas: 1
    image: "victoriametrics/vlagent:v1.49.0"
    pvcSize: "5Gi"
    syslog:
      tcp: 514
      udp: 514
      tlsPort: 6514
    service:
      type: LoadBalancer
      nodePorts:
        tcp: 32399
        udp: 32400
    resources:
      requests: { memory: "64Mi", cpu: "25m" }
      limits: { memory: "256Mi", cpu: "100m" }

  additionalLogWriteEndpoints: []

# ============================================================================
# RBAC
# ============================================================================
rbac:
  create: true
  serviceAccount:
    create: true
    name: "vmagent"
```

### 3.3 Template Files

| Template | K8s Resource | Condition |
|----------|-------------|-----------|
| `vmcluster.yaml` | VMCluster CR (or VMSingle) | `metrics.enabled` |
| `vmagent.yaml` | VMAgent CR | `metrics.enabled` |
| `vmscrape.yaml` | VMPodScrape, VMServiceScrape | `metrics.enabled` + per-source |
| `vmagent-rbac.yaml` | ServiceAccount, Role, RoleBinding, ClusterRole, ClusterRoleBinding | `rbac.create` |
| `vlcluster.yaml` | VLCluster CR | `logs.enabled` |
| `vlagent.yaml` | VLAgent CR | `logs.enabled` |
| `vlagent-config.yaml` | ConfigMap (syslog pipeline) | `logs.enabled` |
| `vlagent-syslog-tls.yaml` | Secret (syslog TLS certs) | `logs.enabled && logs.tls.enabled` |
| `_helpers.tpl` | Template helpers | - |

### 3.4 Migration from Current

| Current File(s) | New Template | Changes |
|-----------------|-------------|---------|
| `victoria-operator-vmcluster.yaml.j2` / `victoria-operator-vmsingle.yaml.j2` | `vmcluster.yaml` | Unified with conditional cluster/single |
| `victoria-operator-vmagent.yaml.j2` | `vmagent.yaml` | Direct values reference |
| `victoria-operator-vmscrape.yaml.j2` | `vmscrape.yaml` | Loop-based per-source |
| `victoria-vmagent-rbac.yaml.j2` | `vmagent-rbac.yaml` | Direct values reference |
| `victorialogs-operator-vlcluster.yaml.j2` | `vlcluster.yaml` | Direct values reference |
| `victorialogs-operator-vlagent.yaml.j2` | `vlagent.yaml` | Direct values reference |
| `victorialogs-vlagent-config.yaml.j2` | `vlagent-config.yaml` | Direct values reference |
| `vlagent-syslog-tls-secret.yaml.j2` | `vlagent-syslog-tls.yaml` | Shared TLS approach |
| `vmagent-scrape-config.yaml.j2` | Replaced by VMScrape CRDs | No longer needed |
| `gen_victoria_certs.sh.j2` | Umbrella `tls-cert-job.yaml` | Moved up to parent chart |
| `victoria-tls-secret.yaml.j2` | Umbrella `tls-secret.yaml` | Shared across charts |
| `victoria-tls-test-job.yaml.j2` | `tests/test-tls.yaml` | Helm test |
| `victoria-statefulset.yaml.j2` | Removed | Operator-only mode |
| `victoria-agent-deployment.yaml.j2` | Removed | Operator-only mode |

---

## 4. iDRAC Sub-Chart (`charts/idrac/`)

### 4.1 Overview

Deploys the iDRAC telemetry StatefulSet with 5 containers: MySQL, ActiveMQ,
iDRAC Telemetry Receiver, KafkaPump, and VictoriaPump.

### 4.2 values.yaml Schema

```yaml
# charts/idrac/values.yaml
enabled: true

replicas: 1                           # Scaled by Omnia based on node count

images:
  receiver: "dellhpcomniaaisolution/idrac_telemetry_receiver:1.2"
  kafkaPump: "dellhpcomniaaisolution/kafkapump:1.2"
  victoriaPump: "dellhpcomniaaisolution/victoriapump:1.2"
  activemq: "rmohr/activemq:5.15.9"
  mysql: "library/mysql:9.3.0"

collectionTargets:
  kafka: true
  victoriaMetrics: true

mysql:
  storage: "1Gi"
  storageClass: ""
  port: 3306
  resources:
    requests: { cpu: "100m", memory: "256Mi" }
    limits: { cpu: "500m", memory: "512Mi" }

activemq:
  ports:
    http: 8161
    openwire: 61616
    stomp: 61613
  resources:
    requests: { cpu: "100m", memory: "512Mi" }
    limits: { cpu: "500m", memory: "1536Mi" }

receiver:
  resources:
    requests: { cpu: "100m", memory: "128Mi" }
    limits: { cpu: "500m", memory: "256Mi" }

kafkaPump:
  enabled: true                        # Linked to collectionTargets.kafka
  skipVerify: true
  resources:
    requests: { cpu: "50m", memory: "128Mi" }
    limits: { cpu: "200m", memory: "512Mi" }

victoriaPump:
  enabled: true                        # Linked to collectionTargets.victoriaMetrics
  metricsPort: 2112
  resources:
    requests: { cpu: "50m", memory: "128Mi" }
    limits: { cpu: "200m", memory: "512Mi" }

service:
  type: ClusterIP

terminationGracePeriodSeconds: 120

# Kafka connection (auto-populated from parent)
kafka:
  bootstrapServers: ""                 # Set by umbrella chart
  tlsSecretName: ""
```

### 4.3 Template Files

| Template | K8s Resource | Condition |
|----------|-------------|-----------|
| `statefulset.yaml` | StatefulSet (5 containers) | `enabled` |
| `service.yaml` | Headless Service | `enabled` |
| `mysql-pvc.yaml` | PVC for MySQL data | `enabled` |
| `_helpers.tpl` | Template helpers | - |

### 4.4 Container Architecture (Preserved)

```
Pod: idrac-telemetry-N
  +---> mysqldb (MySQL 9.3)
  |       - Port 3306
  |       - PVC: mysqldb-storage-claim
  |
  +---> activemq (ActiveMQ 5.15.9)
  |       - Ports: 8161, 61616, 61613
  |       - Internal message bus
  |
  +---> idrac-telemetry-receiver
  |       - SSE receiver from iDRAC BMCs
  |       - Publishes to ActiveMQ
  |
  +---> kafka-pump (conditional)
  |       - Consumes ActiveMQ -> Produces to Kafka
  |       - mTLS via kafkapump user certs
  |
  +---> victoria-pump (conditional)
          - Consumes ActiveMQ -> Exposes Prometheus metrics
          - Port 2112 (/metrics)
```

---

## 5. LDMS Sub-Chart (`charts/ldms/`)

### 5.1 Overview

Evolved from the existing `nersc-ldms-aggr` Helm chart. Deploys LDMS aggregator
and store StatefulSets with Kafka integration.

### 5.2 values.yaml Schema

```yaml
# charts/ldms/values.yaml
enabled: true

image: "dellhpcomniaaisolution/ubuntu-ldms:1.1"

aggregator:
  replicas: 1
  port: 6001                          # Valid: 6001-6100
  transport: sock
  resources:
    requests: { cpu: "250m", memory: "512Mi" }
    limits: { cpu: "1000m", memory: "1Gi" }

store:
  replicas: 1
  port: 6001                          # Valid: 6001-6100
  resources:
    requests: { cpu: "250m", memory: "512Mi" }
    limits: { cpu: "1000m", memory: "1Gi" }

sampler:
  port: 10001                          # Valid: 10001-10100
  plugins:
    - name: meminfo
      config: ""
      interval: 30000000               # Microseconds (30s)
    - name: procstat2
      config: ""
      interval: 30000000
    - name: vmstat
      config: ""
      interval: 30000000
    - name: loadavg
      config: ""
      interval: 30000000
    - name: procnetdev2
      config: ""
      interval: 30000000
      offset: 0

auth:
  # OVIS auth secret - either provide existing secret or values
  existingSecret: ""
  secretWord: ""                       # Generated if empty

munge:
  # Munge key - either provide existing secret or auto-generate
  existingSecret: ""

kafka:
  # Kafka connection for store_avro_kafka
  bootstrapServers: ""                 # Auto-populated from parent
  tlsSecretName: ""                    # kafkapump user certs
  caSecretName: ""                     # Kafka cluster CA

network:
  # Optional ipvlan NetworkAttachmentDefinition
  nad:
    enabled: false
    masterInterface: ""
    ipam: {}

secrets:
  # Inline secret creation (alternative to existingSecret)
  createOvisAuth: true
  createMungeKey: true
```

### 5.3 Template Files

| Template | K8s Resource | Condition |
|----------|-------------|-----------|
| `statefulset-agg.yaml` | StatefulSet (aggregator) | `enabled` |
| `statefulset-store.yaml` | StatefulSet (store) | `enabled` |
| `service-agg.yaml` | ClusterIP Service | `enabled` |
| `service-store.yaml` | Headless Service | `enabled` |
| `secrets.yaml` | Secrets (OVIS auth, Munge key) | `secrets.create*` |
| `network-attachment.yaml` | NetworkAttachmentDefinition | `network.nad.enabled` |
| `_helpers.tpl` | Template helpers | - |

### 5.4 Migration from Current

| Current File | New Template | Changes |
|-------------|-------------|---------|
| `nersc-ldms-aggr/templates/Statefulset.nersc-ldms-agg.yaml` | `statefulset-agg.yaml` | Values from chart, not hardcoded |
| `nersc-ldms-aggr/templates/Statefulset.nersc-ldms-store.yaml` | `statefulset-store.yaml` | Kafka config from values |
| `nersc-ldms-aggr/templates/Service.nersc-ldms-agg.yaml` | `service-agg.yaml` | Standard labels |
| `nersc-ldms-aggr/templates/Service.nersc-ldms-store.yaml` | `service-store.yaml` | Standard labels |
| `nersc-ldms-aggr/templates/NetworkAttachmentDefinition.yaml` | `network-attachment.yaml` | Conditional |
| Ansible tasks: secret creation in `telemetry.sh.j2` | `secrets.yaml` | Native Helm secret management |

---

## 6. Vector Sub-Chart (`charts/vector/`)

### 6.1 Overview

Deploys Vector data pipelines (LDMS and OME bridges) plus their write-buffer
agents (vmagent-vector, vlagent-vector).

### 6.2 values.yaml Schema

```yaml
# charts/vector/values.yaml
enabled: true

image: "timberio/vector:0.45.0-alpine"

ldms:
  enabled: true
  replicas: 2
  resources:
    requests: { memory: "128Mi", cpu: "50m" }
    limits: { memory: "256Mi", cpu: "250m" }
  kafka:
    topic: "ldms"
    consumerGroup: "vector-ldms"
    bootstrapServers: ""
    tlsSecretName: ""
    caSecretName: ""
  pipeline:
    # Lua fan-out transform: 1 Kafka message -> N Prometheus metrics
    luaScript: ""                      # Auto-generated from LDMS schema
    outputEndpoint: ""                 # vmagent-vector:8429

ome:
  enabled: true
  replicas: 2
  resources:
    requests: { memory: "256Mi", cpu: "100m" }
    limits: { memory: "512Mi", cpu: "500m" }
  kafka:
    topicPattern: "^ome\\..*$"
    consumerGroup: "vector-ome"
    bootstrapServers: ""
    tlsSecretName: ""
    caSecretName: ""
  omeIdentifier: "ome"
  metricsEnabled: true
  logsEnabled: true
  pipeline:
    metricsEndpoint: ""                # vmagent-vector:8429
    logsEndpoint: ""                   # vlagent-vector:9427

vmagentVector:
  enabled: true
  replicas: 2
  image: "victoriametrics/vmagent:v1.128.0"
  port: 8429
  pvcSize: "5Gi"
  remoteWriteUrl: ""                   # vminsert:8480
  resources:
    requests: { memory: "128Mi", cpu: "50m" }
    limits: { memory: "256Mi", cpu: "250m" }

vlagentVector:
  enabled: true
  replicas: 2
  image: "victoriametrics/vlagent:v1.49.0"
  port: 9427
  pvcSize: "5Gi"
  remoteWriteUrl: ""                   # vlinsert:9481
  resources:
    requests: { memory: "128Mi", cpu: "50m" }
    limits: { memory: "256Mi", cpu: "250m" }

securityContext:
  runAsUser: 1000
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
  seccompProfile:
    type: RuntimeDefault
```

### 6.3 Template Files

| Template | K8s Resource | Condition |
|----------|-------------|-----------|
| `vector-ldms-deployment.yaml` | Deployment | `ldms.enabled` |
| `vector-ldms-configmap.yaml` | ConfigMap (TOML pipeline) | `ldms.enabled` |
| `vector-ldms-service.yaml` | Service | `ldms.enabled` |
| `vector-ome-deployment.yaml` | Deployment | `ome.enabled` |
| `vector-ome-configmap.yaml` | ConfigMap (TOML pipeline) | `ome.enabled` |
| `vector-ome-service.yaml` | Service | `ome.enabled` |
| `vector-ome-kafkauser.yaml` | KafkaUser (Strimzi) | `ome.enabled` |
| `vmagent-vector.yaml` | Deployment + Service | `vmagentVector.enabled` |
| `vlagent-vector.yaml` | Deployment + Service | `vlagentVector.enabled` |
| `_helpers.tpl` | Template helpers | - |

---

## 7. External Sources Sub-Chart (`charts/external-sources/`)

### 7.1 Overview

Manages external telemetry sources (UFM, VAST, PowerScale) that are NOT deployed
by Omnia but whose metrics/logs are ingested.

### 7.2 values.yaml Schema

```yaml
# charts/external-sources/values.yaml
enabled: true

ufm:
  enabled: false
  endpoint: ""
  port: 9001
  scrapeInterval: "30s"
  scrapeTimeout: "15s"
  tlsMode: "self_signed"              # self_signed | ca_signed
  caCertPath: ""
  authMode: "basic"                    # basic | none
  credentials:
    existingSecret: ""                 # Pre-existing K8s Secret
    username: ""                       # Direct (less secure)
    password: ""

vast:
  enabled: false
  endpoint: ""
  port: 443
  metricsPath: "/api/prometheusmetrics/all"
  scrapeInterval: "30s"
  scrapeTimeout: "15s"
  tlsMode: "self_signed"
  caCertPath: ""
  authMode: "basic"
  credentials:
    existingSecret: ""
    username: ""
    password: ""

powerscale:
  metricsEnabled: true
  logsEnabled: true

  csiVolumeExporter:
    enabled: true
    image: "dellhpcomniaaisolution/csi-volume-exporter:1.0"
    port: 8080
    resources:
      requests: { cpu: "50m", memory: "64Mi" }
      limits: { cpu: "200m", memory: "256Mi" }

  csmMetrics:
    enabled: true
    # Per-cluster deployments
    clusters: []
    # - name: cluster1
    #   secretName: isilon-creds-cluster1
    #   image: "dellemc/csm-metrics-powerscale:v1.7.0"

  otelCollector:
    storageSize: "5Gi"
```

### 7.3 Template Files

| Template | K8s Resource | Condition |
|----------|-------------|-----------|
| `ufm-external-service.yaml` | Service(ExternalName) + Endpoints | `ufm.enabled` |
| `ufm-secret.yaml` | Secret (auth + CA) | `ufm.enabled && !ufm.credentials.existingSecret` |
| `vast-external-service.yaml` | Service(ExternalName) + Endpoints | `vast.enabled` |
| `vast-secret.yaml` | Secret (auth + CA) | `vast.enabled && !vast.credentials.existingSecret` |
| `powerscale-csi-exporter.yaml` | SA, ClusterRole, CRB, Deployment, Service | `powerscale.csiVolumeExporter.enabled` |
| `powerscale-csm-metrics.yaml` | Deployment (per cluster) | `powerscale.csmMetrics.enabled` |
| `_helpers.tpl` | Template helpers | - |

---

## 8. Telemetry Operator Sub-Chart (`charts/telemetry-operator/`)

### 8.1 Overview

Deploys the TelemetryHealth operator and default health policies. Replaces
the `pod-cleanup` CronJob with declarative, graduated remediation.

### 8.2 values.yaml Schema

```yaml
# charts/telemetry-operator/values.yaml
enabled: true

image: "dellhpcomniaaisolution/telemetry-operator:0.1.0"
replicas: 2                           # HA with leader election

resources:
  requests: { cpu: "50m", memory: "64Mi" }
  limits: { cpu: "200m", memory: "128Mi" }

leaderElection:
  enabled: true
  leaseDuration: 15s
  renewDeadline: 10s
  retryPeriod: 2s

metrics:
  enabled: true
  port: 8080
  path: /metrics
  serviceMonitor:
    enabled: true
    interval: "30s"

rbac:
  create: true
  serviceAccount:
    create: true
    name: "telemetry-operator"

defaultPolicy:
  create: true
  rules:
    stuckTerminating:
      enabled: true
      thresholdSeconds: 60
      kafkaThresholdSeconds: 300
      remediation:
        strategy: Graduated
        steps:
          - action: RemoveFinalizers
            delaySeconds: 0
          - action: ForceDelete
            delaySeconds: 10
          - action: CleanPvcLockFiles
            delaySeconds: 5

    crashLoopBackoff:
      enabled: true
      minRestartCount: 5
      remediation:
        strategy: Alert
        severity: warning

    pendingTooLong:
      enabled: true
      thresholdSeconds: 300
      remediation:
        strategy: Alert
        severity: critical
```

### 8.3 CRD Files (`crds/`)

| File | CRD | Scope |
|------|-----|-------|
| `telemetryhealthpolicy.yaml` | `telemetryhealthpolicies.telemetry.omnia.dell.com` | Cluster |
| `telemetryhealthstatus.yaml` | `telemetryhealthstatuses.telemetry.omnia.dell.com` | Namespaced |

### 8.4 Template Files

| Template | K8s Resource | Condition |
|----------|-------------|-----------|
| `operator-deployment.yaml` | Deployment (operator) | `enabled` |
| `operator-rbac.yaml` | SA, ClusterRole, CRB | `rbac.create` |
| `default-health-policy.yaml` | TelemetryHealthPolicy CR | `defaultPolicy.create` |
| `_helpers.tpl` | Template helpers | - |

### 8.5 Operator Go Project Structure

```
telemetry-operator/
  cmd/
    main.go                            # Entry point
  api/
    v1alpha1/
      telemetryhealthpolicy_types.go   # CRD Go types
      telemetryhealthstatus_types.go   # Status CRD Go types
      groupversion_info.go
      zz_generated.deepcopy.go
  internal/
    controllers/
      healthpolicy_controller.go       # Main reconciler
      healthpolicy_controller_test.go
    evaluation/
      rules.go                         # Rule condition evaluators
      terminating.go                   # TerminatingDuration evaluator
      container_state.go               # ContainerState evaluator
      pending.go                       # PendingDuration evaluator
    remediation/
      executor.go                      # Remediation action executor
      finalizer_removal.go
      force_delete.go
      pvc_cleanup.go
      alert.go                         # Prometheus alert generation
  config/
    crd/                               # Generated CRD manifests
    rbac/                              # Generated RBAC manifests
    samples/                           # Example CRs
  Dockerfile
  Makefile
  go.mod
  go.sum
```

### 8.6 Controller Reconciliation Logic

```go
func (r *HealthPolicyReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. Fetch TelemetryHealthPolicy
    policy := &v1alpha1.TelemetryHealthPolicy{}
    if err := r.Get(ctx, req.NamespacedName, policy); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }

    // 2. List pods matching selectors
    podList := &corev1.PodList{}
    listOpts := buildListOptions(policy.Spec.NamespaceSelector, policy.Spec.PodSelector)
    if err := r.List(ctx, podList, listOpts...); err != nil {
        return ctrl.Result{}, err
    }

    // 3. Evaluate rules against each pod
    for _, pod := range podList.Items {
        for _, rule := range policy.Spec.Rules {
            matched, details := r.evaluator.Evaluate(rule, &pod)
            if matched {
                // 4. Execute remediation
                result := r.remediator.Execute(ctx, rule.Remediation, &pod, details)
                // 5. Update TelemetryHealthStatus
                r.updateStatus(ctx, policy, &pod, rule, result)
            }
        }
    }

    // 6. Update metrics
    r.metrics.RecordEvaluation(policy, podList)

    // 7. Requeue after evaluation interval
    return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
}
```

---

## 9. Helm Tests

Each sub-chart includes Helm tests (`templates/tests/`) for post-install
verification:

| Chart | Test | What It Validates |
|-------|------|-------------------|
| `kafka` | `test-kafka-connection.yaml` | Kafka broker connectivity via bootstrap |
| `kafka` | `test-tls-handshake.yaml` | mTLS certificate validation |
| `victoria-metrics` | `test-vm-write.yaml` | Metric write + read via vminsert/vmselect |
| `victoria-metrics` | `test-vl-write.yaml` | Log write + query via vlinsert/vlselect |
| `idrac` | `test-mysql-connection.yaml` | MySQL container readiness |
| `ldms` | `test-aggregator-health.yaml` | LDMS aggregator daemon health |
| `vector` | `test-vector-health.yaml` | Vector API healthcheck |
| `telemetry-operator` | `test-operator-health.yaml` | Operator pod readiness + metrics endpoint |

Run all tests:
```bash
helm test omnia-telemetry -n telemetry
```

---

## 10. Mapping: Current Files to New Chart Structure

| Current File | New Location | Notes |
|-------------|-------------|-------|
| `telemetry.sh.j2` | Eliminated | Replaced by `helm install` |
| `kustomization.yaml.j2` | Eliminated | Replaced by Helm chart dependencies |
| `cleanup_telemetry.sh.j2` | `helm uninstall` + operator cleanup | `helm uninstall` handles resource cleanup |
| `telemetry_namespace_creation.yaml.j2` | `templates/namespace.yaml` | Pre-install hook |
| `telemetry_secret_creation.yaml.j2` | Per-chart `secrets.yaml` | Scoped to component |
| `telemetry_cleaner_rbac.yaml.j2` | `charts/telemetry-operator/templates/operator-rbac.yaml` | Operator RBAC |
| `telemetry_pod_cleanup.yaml.j2` | Eliminated | Replaced by TelemetryHealth operator |
| `kafka.kafka.yaml.j2` | `charts/kafka/templates/kafka-cluster.yaml` | Go templates |
| `kafka.kafka_bridge*.yaml.j2` | `charts/kafka/templates/kafka-bridge.yaml` | Merged |
| `kafka.topic.yaml.j2` | `charts/kafka/templates/kafka-topics.yaml` | Loop-based |
| `kafka.kafkapump_user.yaml.j2` | `charts/kafka/templates/kafka-users.yaml` | Combined |
| `kafka.tls_test_job.yaml.j2` | `charts/kafka/templates/tests/test-tls.yaml` | Helm test |
| `victoria-operator-vmcluster.yaml.j2` | `charts/victoria-metrics/templates/vmcluster.yaml` | Go templates |
| `victoria-operator-vmsingle.yaml.j2` | `charts/victoria-metrics/templates/vmcluster.yaml` | Unified |
| `victoria-operator-vmagent.yaml.j2` | `charts/victoria-metrics/templates/vmagent.yaml` | Go templates |
| `victoria-operator-vmscrape.yaml.j2` | `charts/victoria-metrics/templates/vmscrape.yaml` | Loop-based |
| `victoria-vmagent-rbac.yaml.j2` | `charts/victoria-metrics/templates/vmagent-rbac.yaml` | Go templates |
| `victoria-tls-secret.yaml.j2` | `templates/tls-secret.yaml` | Umbrella chart |
| `gen_victoria_certs.sh.j2` | `templates/tls-cert-job.yaml` | Helm hook |
| `victoria-tls-test-job.yaml.j2` | `charts/victoria-metrics/templates/tests/test-tls.yaml` | Helm test |
| `victoria-statefulset.yaml.j2` | Removed | Operator-only mode |
| `victoria-agent-deployment.yaml.j2` | Removed | Operator-only mode |
| `victorialogs-operator-vlcluster.yaml.j2` | `charts/victoria-metrics/templates/vlcluster.yaml` | Go templates |
| `victorialogs-operator-vlagent.yaml.j2` | `charts/victoria-metrics/templates/vlagent.yaml` | Go templates |
| `victorialogs-vlagent-config.yaml.j2` | `charts/victoria-metrics/templates/vlagent-config.yaml` | Go templates |
| `vlagent-syslog-tls-secret.yaml.j2` | `charts/victoria-metrics/templates/vlagent-syslog-tls.yaml` | Go templates |
| `vmagent-scrape-config.yaml.j2` | Replaced by `vmscrape.yaml` (VMScrape CRDs) | No ConfigMap |
| `idrac_telemetry_statefulset.yaml.j2` | `charts/idrac/templates/statefulset.yaml` | Go templates |
| `values.yaml.j2` (LDMS) | `charts/ldms/values.yaml` | Static values |
| `vector-ldms-*.yaml.j2` | `charts/vector/templates/vector-ldms-*.yaml` | Go templates |
| `vector-ome-*.yaml.j2` | `charts/vector/templates/vector-ome-*.yaml` | Go templates |
| `vmagent-vector-deployment.yaml.j2` | `charts/vector/templates/vmagent-vector.yaml` | Go templates |
| `vlagent-vector-deployment.yaml.j2` | `charts/vector/templates/vlagent-vector.yaml` | Go templates |
| `ufm-external-service.yaml.j2` | `charts/external-sources/templates/ufm-external-service.yaml` | Go templates |
| `ufm-telemetry-secret.yaml.j2` | `charts/external-sources/templates/ufm-secret.yaml` | Go templates |
| `vast-external-service.yaml.j2` | `charts/external-sources/templates/vast-external-service.yaml` | Go templates |
| `vast-telemetry-secret.yaml.j2` | `charts/external-sources/templates/vast-secret.yaml` | Go templates |
| `csi-volume-exporter.yaml.j2` | `charts/external-sources/templates/powerscale-csi-exporter.yaml` | Go templates |
| `csm-metrics-deployment-direct.yaml.j2` | `charts/external-sources/templates/powerscale-csm-metrics.yaml` | Go templates |
| `deploy_powerscale_telemetry.sh.j2` | Eliminated | Helm handles deployment |
| `verify_powerscale_telemetry.sh.j2` | `charts/external-sources/templates/tests/test-powerscale.yaml` | Helm test |
| `verify_powerscale_syslog.sh.j2` | `charts/external-sources/templates/tests/test-syslog.yaml` | Helm test |
| `input/telemetry_config.yml` | `values.yaml` / `values-omnia.yaml` | Helm values |
| `input/telemetry_storage_config.yml` | Per-chart `values.yaml` resources sections | Distributed |
| `provision/roles/telemetry/vars/main.yml` | Eliminated | Values in Helm chart |
| `derive_sink_support_flags.yml` | `_helpers.tpl` (template functions) | Helm logic |
| `generate_telemetry_deployments.yml` | Simplified to produce `values-override.yaml` | ~20 lines |
| `generate_telemetry_script.yml` | Simplified to `helm install` command | ~5 lines |
| `telemetry_prereq.yml` | Partially retained (NFS mount, image loading) | Reduced scope |
