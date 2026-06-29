# Engineering Spec (HLD) - Omnia Telemetry Helm Chart Redesign

**Version**: 1.0.0-draft
**Date**: 2026-06-26
**Authors**: Telemetry Architecture Team

---

## 1. Executive Summary

This document describes the high-level design for replacing the current monolithic
kustomize + shell-script telemetry deployment with a top-level Helm umbrella chart.
The new architecture enables standalone deployment of the telemetry stack independent
of Omnia, while preserving Omnia as an optional integration layer. Health monitoring
transitions from ad-hoc CronJobs to a custom Kubernetes operator with declarative
CRDs.

---

## 2. Current State Analysis

### 2.1 Deployment Pipeline (As-Is)

```
Ansible Playbooks
  |
  v
Jinja2 Template Rendering
  |
  v
NFS Share (rendered manifests)
  |
  v
Cloud-Init (first K8s control plane boot)
  |
  v
telemetry.sh (shell script)
  |
  +---> kubectl apply -f (namespace)
  +---> helm install (Strimzi Kafka Operator)
  +---> helm install (VictoriaMetrics Operator)
  +---> kubectl apply -k (kustomize - all component manifests)
  +---> helm install (LDMS Aggregator)
  +---> shell include (PowerScale CSM Observability)
```

### 2.2 Current Pain Points

| Problem | Impact | Severity |
|---------|--------|----------|
| Monolithic kustomize with 95-line Jinja2 template | Cannot deploy components independently; all-or-nothing | High |
| Shell script as deployment entry point | No rollback, no dependency resolution, no lifecycle hooks | High |
| CronJob-based pod cleanup (every 3 min) | Brute-force remediation; masks root causes; no observability | Medium |
| Mixed deployment mechanisms (Helm + kustomize + raw kubectl) | Inconsistent upgrade/rollback story across components | High |
| Ansible+Jinja2 renders all configuration at build time | Cannot change configuration without full re-provision | Medium |
| No way to deploy telemetry without Omnia | Prevents standalone testing, development, or external adoption | High |
| 40+ Jinja2 templates tightly coupled to Ansible vars | Difficult to test, validate, or version independently | Medium |

### 2.3 Components Inventory

| Component | Current Mechanism | K8s Resources | Dependencies |
|-----------|-------------------|---------------|--------------|
| Namespace + Secrets | kustomize (raw YAML) | Namespace, Secret x2 | None |
| Strimzi Kafka Operator | Helm (tarball on NFS) | Deployment, CRDs | Namespace |
| Kafka Cluster | kustomize (Strimzi CRDs) | KafkaNodePool, Kafka, KafkaTopic, KafkaUser, KafkaBridge, Service | Strimzi Operator |
| VictoriaMetrics Operator | Helm (tarball on NFS) | Deployment, CRDs | Namespace |
| VictoriaMetrics | kustomize (VM Operator CRDs) | VMCluster/VMSingle, VMAgent, VMPodScrape, VMServiceScrape, RBAC | VM Operator |
| VictoriaLogs | kustomize (VM Operator CRDs) | VLCluster, VLAgent, ConfigMap | VM Operator |
| iDRAC Telemetry | kustomize (raw YAML) | StatefulSet, Service | Kafka (optional), VictoriaMetrics (optional) |
| LDMS Aggregator | Helm (chart on NFS) | StatefulSet x2, Service x2 | Kafka, Munge secrets |
| Vector-LDMS | kustomize (raw YAML) | Deployment, ConfigMap, Service | Kafka, VictoriaMetrics |
| Vector-OME | kustomize (raw YAML) | Deployment, ConfigMap, Service, KafkaUser | Kafka, VictoriaMetrics/Logs |
| vmagent-vector | kustomize (raw YAML) | Deployment, Service | VictoriaMetrics |
| vlagent-vector | kustomize (raw YAML) | Deployment, Service | VictoriaLogs |
| PowerScale | Shell script (Helm) | Deployment, Service, RBAC, PVC | VictoriaMetrics, cert-manager |
| UFM | kustomize (raw YAML) | Service, Endpoints, Secret | VictoriaMetrics |
| VAST | kustomize (raw YAML) | Service, Endpoints, Secret | VictoriaMetrics |
| Pod Cleanup | kustomize (CronJob) | CronJob, RBAC | All pods |
| TLS Certs | Shell script (openssl) | Secret | VictoriaMetrics/Logs |

---

## 3. Target Architecture

### 3.1 Design Principles

1. **Helm-native**: Single `helm install` deploys the entire stack
2. **Standalone-first**: Deployable without Omnia; Omnia is an integration layer
3. **Feature toggles**: Every component enabled/disabled via `values.yaml`
4. **Child chart composition**: Each major component is a separate sub-chart
5. **Operator-managed health**: CRD+controller replaces CronJob cleanup
6. **Declarative configuration**: No shell scripts in the deployment path
7. **Upgrade-safe**: `helm upgrade` handles all component lifecycle transitions

### 3.2 Umbrella Chart Structure

```
omnia-telemetry/                          # Top-level umbrella chart
  Chart.yaml                              # type: application, version: 1.0.0
  values.yaml                             # Unified configuration surface
  values-standalone.yaml                  # Standalone defaults (no Omnia)
  values-omnia.yaml                       # Omnia-integrated defaults
  templates/
    _helpers.tpl                          # Shared template helpers
    namespace.yaml                        # Telemetry namespace
    tls-secret.yaml                       # Shared TLS certificate secret
    tls-cert-job.yaml                     # Pre-install hook: TLS cert generation
    NOTES.txt                             # Post-install instructions
  charts/
    kafka/                                # Sub-chart: Strimzi Kafka
      Chart.yaml
      values.yaml
      templates/
        strimzi-operator.yaml             # Helm dependency or raw manifest
        kafka-cluster.yaml                # Kafka + KafkaNodePool CRDs
        kafka-bridge.yaml                 # KafkaBridge + LoadBalancer
        kafka-topics.yaml                 # KafkaTopic CRDs (conditional)
        kafka-users.yaml                  # KafkaUser CRDs
        _helpers.tpl
    victoria-metrics/                     # Sub-chart: VictoriaMetrics + Logs
      Chart.yaml
      values.yaml
      templates/
        vm-operator.yaml                  # Helm dependency or raw manifest
        vmcluster.yaml                    # VMCluster / VMSingle CR
        vmagent.yaml                      # VMAgent CR
        vmscrape.yaml                     # VMPodScrape + VMServiceScrape CRs
        vmagent-rbac.yaml                 # ServiceAccount, Role, RoleBinding
        vlcluster.yaml                    # VLCluster CR (logs)
        vlagent.yaml                      # VLAgent CR (syslog receiver)
        vlagent-config.yaml               # VLAgent ConfigMap
        _helpers.tpl
    idrac/                                # Sub-chart: iDRAC Telemetry
      Chart.yaml
      values.yaml
      templates/
        statefulset.yaml                  # Multi-container StatefulSet
        service.yaml                      # Headless Service
        mysql-pvc.yaml                    # MySQL PVC
        _helpers.tpl
    ldms/                                 # Sub-chart: LDMS Aggregator + Store
      Chart.yaml                          # Evolved from nersc-ldms-aggr
      values.yaml
      templates/
        statefulset-agg.yaml              # LDMS Aggregator StatefulSet
        statefulset-store.yaml            # LDMS Store StatefulSet
        service-agg.yaml                  # Aggregator Service
        service-store.yaml                # Store Headless Service
        secrets.yaml                      # OVIS auth + Munge key
        network-attachment.yaml           # Optional ipvlan NAD
        _helpers.tpl
    vector/                               # Sub-chart: Vector Bridges
      Chart.yaml
      values.yaml
      templates/
        vector-ldms-deployment.yaml       # Vector-LDMS Deployment
        vector-ldms-configmap.yaml        # Vector-LDMS pipeline config
        vector-ldms-service.yaml
        vector-ome-deployment.yaml        # Vector-OME Deployment
        vector-ome-configmap.yaml         # Vector-OME pipeline config
        vector-ome-service.yaml
        vector-ome-kafkauser.yaml         # Dedicated KafkaUser
        vmagent-vector.yaml               # Metrics write-buffer
        vlagent-vector.yaml               # Logs write-buffer
        _helpers.tpl
    external-sources/                     # Sub-chart: UFM, VAST, PowerScale
      Chart.yaml
      values.yaml
      templates/
        ufm-external-service.yaml
        ufm-secret.yaml
        vast-external-service.yaml
        vast-secret.yaml
        powerscale-csi-exporter.yaml
        powerscale-csm-metrics.yaml
        _helpers.tpl
    telemetry-operator/                   # Sub-chart: Health Operator
      Chart.yaml
      values.yaml
      crds/
        telemetryhealthpolicy.yaml        # CRD definition
        telemetryhealthstatus.yaml        # CRD definition
      templates/
        operator-deployment.yaml
        operator-rbac.yaml
        default-health-policy.yaml        # Default TelemetryHealthPolicy CR
        _helpers.tpl
```

### 3.3 High-Level Data Flow (Unchanged)

The data flow architecture is preserved from the current system. Only the
deployment mechanism changes.

```
SOURCES                           BRIDGES                    SINKS
+----------+                   +------------+          +-----------------+
| iDRAC    |---ActiveMQ------->| KafkaPump  |--------->| Kafka           |
|          |---ActiveMQ------->| VicPump    |--+       |                 |
+----------+                   +------------+  |       | VictoriaMetrics |
+----------+                   +------------+  |       |                 |
| LDMS     |---store_avro----->| Kafka      |--+------>| VictoriaLogs    |
| samplers |   kafka           | (Strimzi)  |  |       +-----------------+
+----------+                   +-----+------+  |              ^
+----------+                         |         |              |
| OME      |---Kafka topics----------+         |              |
+----------+                   +-----v------+  |              |
                               | Vector-LDMS|--+--vmagent---->|
                               | Vector-OME |--+--vlagent---->|
                               +------------+
+----------+                                          +-------v---------+
|PowerScale|---OTEL Collector---vmagent(shared)------>| VictoriaMetrics |
+----------+                                          +-----------------+
+----------+                                          +-------v---------+
| UFM/VAST |---Prometheus scrape---vmagent(shared)--->| VictoriaMetrics |
+----------+                                          +-----------------+
```

### 3.4 Deployment Ordering

Helm hooks and chart dependencies enforce correct ordering:

```
Phase 0: pre-install hooks
  +---> TLS certificate generation (Job, hook-weight: -10)
  +---> Namespace creation (hook-weight: -5)

Phase 1: Operators (dependencies in Chart.yaml)
  +---> Strimzi Kafka Operator (if kafka.enabled)
  +---> VictoriaMetrics Operator (if victoria-metrics.enabled)

Phase 2: Infrastructure (after operators, via hook-weight or init-containers)
  +---> Kafka Cluster + Topics + Users + Bridge
  +---> VMCluster / VMSingle + VMAgent + VMScrape
  +---> VLCluster + VLAgent

Phase 3: Sources
  +---> iDRAC StatefulSet
  +---> LDMS Aggregator + Store
  +---> External Sources (UFM, VAST, PowerScale)

Phase 4: Bridges
  +---> Vector-LDMS (needs Kafka + VictoriaMetrics)
  +---> Vector-OME (needs Kafka + VictoriaMetrics/Logs)
  +---> vmagent-vector, vlagent-vector

Phase 5: Operator CRs
  +---> TelemetryHealthPolicy (default health rules)
```

Ordering is enforced through:
- **Chart.yaml `dependencies`**: Operators install before CRs
- **Helm hooks**: TLS certs and namespace created pre-install
- **`initContainers`**: Pods wait for upstream services (e.g., Vector waits for Kafka)
- **Operator reconciliation**: CRD-based resources are naturally ordered by their operators

---

## 4. Helm Values Architecture

### 4.1 Top-Level values.yaml Structure

```yaml
# omnia-telemetry/values.yaml
# ============================================================================
# GLOBAL SETTINGS
# ============================================================================
global:
  namespace: telemetry
  imageRegistry: docker.io            # Override for air-gapped environments
  imagePullSecrets: []
  storageClass: ""                     # Default StorageClass (empty = cluster default)

# ============================================================================
# TLS CONFIGURATION
# ============================================================================
tls:
  enabled: true
  certManager:
    enabled: false                     # Use cert-manager instead of self-signed
    issuerRef: {}
  selfSigned:
    enabled: true                      # Generate self-signed CA + certs
    validity: 3650                     # Days
    renewBefore: 30                    # Days before expiry to regenerate
  existingSecret: ""                   # Use pre-existing TLS secret

# ============================================================================
# SOURCES
# ============================================================================
sources:
  idrac:
    enabled: true
    collectionTargets:
      - victoria_metrics
      - kafka
  ldms:
    enabled: true
    collectionTargets:
      - kafka
  dcgm:
    enabled: true
  powerscale:
    metricsEnabled: true
    logsEnabled: true
    collectionTargets:
      - victoria_metrics
      - victoria_logs
  ufm:
    metricsEnabled: false
    logsEnabled: false
    collectionTargets:
      - victoria_metrics
      - victoria_logs
  vast:
    metricsEnabled: false
    logsEnabled: false
    collectionTargets:
      - victoria_metrics
      - victoria_logs
  ome:
    metricsEnabled: true
    logsEnabled: true
    collectionTargets:
      - kafka

# ============================================================================
# BRIDGES
# ============================================================================
bridges:
  vectorLdms:
    enabled: true
  vectorOme:
    metricsEnabled: true
    logsEnabled: true
    omeIdentifier: "ome"

# ============================================================================
# CHILD CHART OVERRIDES
# ============================================================================
kafka:
  enabled: true                        # Auto-derived from sources + bridges
  # ... (see Component Spec for full schema)

victoria-metrics:
  enabled: true                        # Auto-derived from sources + bridges
  # ... (see Component Spec for full schema)

idrac:
  enabled: true
  # ...

ldms:
  enabled: true
  # ...

vector:
  enabled: true
  # ...

external-sources:
  enabled: true
  # ...

telemetry-operator:
  enabled: true
  # ...
```

### 4.2 Values Derivation Logic

The top-level chart templates compute sink enablement from source configuration,
mirroring the current `derive_sink_support_flags.yml` logic but in Helm template
functions:

```
# _helpers.tpl (pseudocode)

{{- define "omnia-telemetry.kafkaRequired" -}}
  {{- if or
    (and .Values.sources.idrac.enabled (has "kafka" .Values.sources.idrac.collectionTargets))
    (and .Values.sources.ldms.enabled (has "kafka" .Values.sources.ldms.collectionTargets))
    (and (or .Values.sources.ome.metricsEnabled .Values.sources.ome.logsEnabled)
         (has "kafka" .Values.sources.ome.collectionTargets))
    .Values.bridges.vectorLdms.enabled
    (or .Values.bridges.vectorOme.metricsEnabled .Values.bridges.vectorOme.logsEnabled)
  -}}true{{- end -}}
{{- end -}}

{{- define "omnia-telemetry.victoriaMetricsRequired" -}}
  {{- if or
    (and .Values.sources.idrac.enabled (has "victoria_metrics" .Values.sources.idrac.collectionTargets))
    (and .Values.sources.powerscale.metricsEnabled (has "victoria_metrics" .Values.sources.powerscale.collectionTargets))
    (and .Values.sources.ufm.metricsEnabled (has "victoria_metrics" .Values.sources.ufm.collectionTargets))
    (and .Values.sources.vast.metricsEnabled (has "victoria_metrics" .Values.sources.vast.collectionTargets))
    .Values.bridges.vectorLdms.enabled
    .Values.bridges.vectorOme.metricsEnabled
  -}}true{{- end -}}
{{- end -}}
```

### 4.3 Omnia Integration Layer

When deployed via Omnia, the Ansible playbooks produce a `values-override.yaml`
instead of generating individual manifests. The playbook:

1. Reads `input/telemetry_config.yml` and `input/telemetry_storage_config.yml`
2. Renders a single `values-override.yaml` mapping Omnia config to Helm values
3. Runs `helm install omnia-telemetry ./omnia-telemetry -f values-override.yaml`

This replaces the current 296-line `generate_telemetry_deployments.yml` and
109-line `telemetry.sh.j2`.

---

## 5. TelemetryHealth Operator Design

### 5.1 Motivation

The current `pod-cleanup` CronJob runs every 3 minutes and:
- Force-deletes pods stuck in Terminating state
- Removes finalizers from non-Kafka pods
- Spawns busybox pods to clean PVC lock files
- Has no visibility into *why* pods are stuck
- Cannot differentiate between transient and persistent failures

This is replaced by a Kubernetes operator that:
- Watches pod states declaratively via CRD-defined health policies
- Performs graduated remediation (restart -> delete -> alert)
- Exposes health status as a queryable K8s resource
- Integrates with VictoriaMetrics for alerting

### 5.2 Custom Resource Definitions

#### TelemetryHealthPolicy (Cluster-scoped)

```yaml
apiVersion: telemetry.omnia.dell.com/v1alpha1
kind: TelemetryHealthPolicy
metadata:
  name: default-telemetry-health
spec:
  # Target selector
  namespaceSelector:
    matchLabels:
      app.kubernetes.io/part-of: omnia-telemetry
  podSelector:
    matchLabels: {}                    # All pods in matching namespaces

  # Health check rules
  rules:
    - name: stuck-terminating
      description: "Detect pods stuck in Terminating state"
      condition:
        type: TerminatingDuration
        thresholdSeconds: 60
        # Override per component
        overrides:
          - labelSelector:
              matchLabels:
                app.kubernetes.io/component: kafka
            thresholdSeconds: 300
      remediation:
        strategy: Graduated
        steps:
          - action: RemoveFinalizers
            delaySeconds: 0
            excludeLabelSelector:
              matchLabels:
                app.kubernetes.io/component: kafka
          - action: ForceDelete
            delaySeconds: 10
          - action: CleanPvcLockFiles
            delaySeconds: 5
            pvcPatterns:
              - "*.lock"
              - "*.sock"
              - "*.pid"

    - name: crash-loop-backoff
      description: "Detect pods in CrashLoopBackOff"
      condition:
        type: ContainerState
        state: CrashLoopBackOff
        minRestartCount: 5
      remediation:
        strategy: Alert
        alertLabels:
          severity: warning
          team: telemetry

    - name: pending-too-long
      description: "Detect pods pending for too long"
      condition:
        type: PendingDuration
        thresholdSeconds: 300
      remediation:
        strategy: Alert
        alertLabels:
          severity: critical
          team: telemetry

  # Observability
  metrics:
    enabled: true
    port: 8080
    path: /metrics
```

#### TelemetryHealthStatus (Namespace-scoped, operator-managed)

```yaml
apiVersion: telemetry.omnia.dell.com/v1alpha1
kind: TelemetryHealthStatus
metadata:
  name: telemetry-health
  namespace: telemetry
status:
  lastEvaluated: "2026-06-26T10:30:00Z"
  overallHealth: Degraded             # Healthy | Degraded | Unhealthy
  components:
    - name: kafka
      health: Healthy
      pods:
        total: 6
        ready: 6
        terminating: 0
    - name: victoria-metrics
      health: Healthy
      pods:
        total: 7
        ready: 7
        terminating: 0
    - name: idrac-telemetry
      health: Degraded
      pods:
        total: 3
        ready: 2
        terminating: 1
      activeRemediations:
        - rule: stuck-terminating
          pod: idrac-telemetry-2
          action: ForceDelete
          startedAt: "2026-06-26T10:28:00Z"
  remediationHistory:
    - timestamp: "2026-06-26T10:28:05Z"
      rule: stuck-terminating
      pod: idrac-telemetry-2
      action: ForceDelete
      result: Success
```

### 5.3 Operator Controller Architecture

```
TelemetryHealthPolicy Controller
  |
  +---> Watch: TelemetryHealthPolicy CRs
  +---> Watch: Pods in target namespaces
  +---> Watch: PVCs in target namespaces
  |
  +---> Reconcile Loop (every 30s per policy):
  |       1. List pods matching selectors
  |       2. Evaluate each rule's condition against pod state
  |       3. For matched pods:
  |           a. Check if remediation already in-progress
  |           b. Execute remediation step (graduated or alert)
  |           c. Update TelemetryHealthStatus CR
  |       4. Emit Prometheus metrics:
  |           - telemetry_health_pods_total{component, state}
  |           - telemetry_health_remediations_total{rule, action, result}
  |           - telemetry_health_evaluation_duration_seconds
  |
  +---> Leader Election (for HA)
  +---> Metrics Server (:8080)
```

### 5.4 Operator Implementation

The operator is implemented in Go using `controller-runtime` (kubebuilder scaffold):

| Package | Purpose |
|---------|---------|
| `api/v1alpha1/` | CRD Go types for TelemetryHealthPolicy and TelemetryHealthStatus |
| `controllers/` | Reconciler for TelemetryHealthPolicy |
| `pkg/remediation/` | Remediation action executors (finalizer removal, force delete, PVC cleanup) |
| `pkg/evaluation/` | Rule condition evaluators (TerminatingDuration, ContainerState, PendingDuration) |

The operator is packaged as a container image and deployed via the `telemetry-operator`
sub-chart.

---

## 6. Dependency Management

### 6.1 Operator Dependencies (Chart.yaml)

The umbrella chart declares Strimzi and VictoriaMetrics operators as conditional
Helm dependencies:

```yaml
# omnia-telemetry/Chart.yaml
apiVersion: v2
name: omnia-telemetry
type: application
version: 1.0.0
appVersion: "1.0.0"
description: Dell Omnia Telemetry Stack

dependencies:
  - name: strimzi-kafka-operator
    version: "0.48.0"
    repository: "https://strimzi.io/charts/"
    condition: kafka.enabled
    alias: strimzi

  - name: victoria-metrics-operator
    version: "0.59.0"
    repository: "https://victoriametrics.github.io/helm-charts/"
    condition: victoria-metrics.operatorEnabled
    alias: vmoperator
```

For air-gapped environments, the operator chart tarballs are bundled in the
`charts/` directory (same as current NFS-based tarball approach).

### 6.2 CRD Installation Strategy

CRDs for Strimzi and VictoriaMetrics are installed by their respective operators.
The umbrella chart uses `helm.sh/hook: pre-install` jobs to wait for CRD
availability before creating CRs:

```yaml
# templates/wait-for-crds.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "omnia-telemetry.fullname" . }}-wait-crds
  annotations:
    "helm.sh/hook": post-install
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": hook-succeeded,hook-failed
spec:
  template:
    spec:
      containers:
        - name: wait
          image: bitnami/kubectl:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              {{- if .Values.kafka.enabled }}
              until kubectl get crd kafkas.kafka.strimzi.io; do sleep 2; done
              {{- end }}
              {{- if (include "omnia-telemetry.victoriaMetricsRequired" .) }}
              until kubectl get crd vmclusters.operator.victoriametrics.com; do sleep 2; done
              {{- end }}
      restartPolicy: Never
```

---

## 7. TLS Certificate Management

### 7.1 Current Approach
A 183-line shell script (`gen_victoria_certs.sh.j2`) generates a self-signed CA and
server certificate with 50+ SANs covering all Victoria component FQDNs.

### 7.2 New Approach

Three options, selectable via `tls.mode`:

| Mode | Description | Use Case |
|------|-------------|----------|
| `selfSigned` | Pre-install hook Job generates CA + certs, stores in Secret | Default, standalone |
| `certManager` | cert-manager Certificate CR auto-manages lifecycle | Production clusters with cert-manager |
| `existing` | User provides pre-existing TLS Secret | Enterprise PKI integration |

The TLS cert generation Job (selfSigned mode) uses the same openssl logic as the
current script but is a proper Helm hook:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-tls-init
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-10"
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  template:
    spec:
      containers:
        - name: tls-gen
          image: alpine/openssl:latest
          command: ["/bin/sh", "/scripts/gen-certs.sh"]
          volumeMounts:
            - name: scripts
              mountPath: /scripts
      volumes:
        - name: scripts
          configMap:
            name: {{ .Release.Name }}-tls-scripts
      restartPolicy: Never
```

SANs are dynamically computed from enabled components in the `_helpers.tpl`:

```
{{- define "omnia-telemetry.tlsSANs" -}}
DNS:victoria-tls-certs.{{ .Release.Namespace }}.svc
{{- if (include "omnia-telemetry.victoriaMetricsRequired" .) }}
DNS:vmselect-omnia-telemetry.{{ .Release.Namespace }}.svc
DNS:vminsert-omnia-telemetry.{{ .Release.Namespace }}.svc
DNS:vmstorage-omnia-telemetry-*.{{ .Release.Namespace }}.svc
...
{{- end }}
{{- end -}}
```

---

## 8. Upgrade Strategy

### 8.1 Helm Upgrade Flow

```
helm upgrade omnia-telemetry ./omnia-telemetry -f values.yaml
  |
  +---> Pre-upgrade hook: TLS cert rotation (if needed)
  +---> Operator upgrades (Strimzi, VM Operator)
  +---> CRD updates (automatic via operators)
  +---> StatefulSet rolling updates (Kafka, VictoriaMetrics, LDMS)
  +---> Deployment rolling updates (Vector, iDRAC, external sources)
  +---> Post-upgrade hook: Health verification Job
```

### 8.2 Migration from Current System

See [03-Implementation-Plan.md](./03-Implementation-Plan.md) for detailed
phased migration strategy.

### 8.3 Rollback

Helm's built-in `helm rollback` handles all components:

```bash
# View revision history
helm history omnia-telemetry -n telemetry

# Rollback to previous revision
helm rollback omnia-telemetry 1 -n telemetry
```

StatefulSets (Kafka, VictoriaMetrics, LDMS) use `OnDelete` update strategy
during migration to prevent data loss from premature pod restarts.

---

## 9. Air-Gapped / Offline Support

### 9.1 Current Approach
Helm chart tarballs and container images are pre-loaded onto NFS share during
Omnia provisioning via `load_service_images.yml`.

### 9.2 New Approach

The umbrella chart supports offline deployment through:

1. **Bundled dependencies**: Operator charts stored in `charts/` directory
2. **Image registry override**: `global.imageRegistry` redirects all image pulls
3. **Image list generation**: `helm template` + image extraction script generates
   the complete list of required images for pre-loading

```yaml
# values-airgapped.yaml
global:
  imageRegistry: registry.internal.corp:5000
  imagePullSecrets:
    - name: registry-credentials
```

---

## 10. Decision Log

| Decision | Rationale | Alternatives Considered |
|----------|-----------|------------------------|
| Umbrella chart (not Helmfile) | Single `helm install`, simpler lifecycle, native dependency resolution | Helmfile (more flexible but adds tooling dependency) |
| Sub-charts (not library charts) | Each component independently testable and deployable | Library charts (less isolation) |
| Custom operator for health (not OPA/Kyverno) | Domain-specific remediation logic, graduated response, status CRD | Kyverno policies (limited to mutation/validation, no active remediation) |
| Go operator (not shell-based) | Type safety, controller-runtime ecosystem, leader election, metrics | Kopf/Python (slower, less K8s-native), shell operator (limited) |
| Self-signed TLS as default | Zero external dependencies for quick start | cert-manager default (requires pre-installed cert-manager) |
| Keep Strimzi/VM operators as dependencies | Leverage mature, upstream operators rather than reimplementing | Custom Kafka/VM deployments (high maintenance burden) |
