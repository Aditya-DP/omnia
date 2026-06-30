# Test Specification - Omnia Telemetry Helm Chart

**Version**: 1.0.0
**Date**: 2026-06-29
**Parent**: [Engineering Spec (HLD)](./01-Engineering-Spec-HLD.md)

---

## 1. Test Strategy Overview

### 1.1 Test Levels

| Level | Tool | Scope | Automated |
|-------|------|-------|-----------|
| Unit | `helm-unittest` | Individual template rendering | Yes |
| Lint | `helm lint` | Chart structure and syntax | Yes |
| Render | `helm template` | Full chart YAML generation | Yes |
| Schema | `helm template` + `kubeconform` | K8s API schema validation | Yes |
| Integration | `helm install` on Kind | Live cluster deployment | Manual |
| E2E | `helm test` hooks | In-cluster connectivity | Manual |

### 1.2 Test Matrix

Each test validates one or more of these dimensions:
- **Default values**: Templates render correctly with no overrides
- **Feature toggles**: Components correctly appear/disappear when enabled/disabled
- **Value overrides**: Custom values propagate to the correct template fields
- **Conditional logic**: TLS, collection targets, deployment modes
- **Resource correctness**: Labels, namespaces, naming, resource types
- **Security**: RBAC, security contexts, secret handling

---

## 2. Unit Test Specification

### 2.1 Umbrella Chart Tests

| Test ID | Template | Assertion | Priority |
|---------|----------|-----------|----------|
| U-001 | namespace.yaml | Namespace created with correct name from `global.namespace` | P0 |
| U-002 | namespace.yaml | Pre-install hook annotation present | P0 |
| U-003 | namespace.yaml | Standard labels applied | P1 |
| U-004 | tls-cert-job.yaml | Job rendered when `tls.selfSigned.enabled=true` | P0 |
| U-005 | tls-cert-job.yaml | Job NOT rendered when `tls.existingSecret` is set | P0 |
| U-006 | tls-cert-job.yaml | Cert validity days from values | P1 |
| U-007 | tls-cert-job.yaml | SANs include all Victoria and Kafka service FQDNs | P1 |
| U-008 | tls-cert-job.yaml | Hook weights ensure correct ordering (SA < scripts < job) | P1 |
| U-009 | tls-cert-job.yaml | Job NOT rendered when `tls.enabled=false` | P0 |

### 2.2 Kafka Sub-Chart Tests

| Test ID | Template | Assertion | Priority |
|---------|----------|-----------|----------|
| K-001 | kafka-cluster.yaml | Controller KafkaNodePool created with correct replicas | P0 |
| K-002 | kafka-cluster.yaml | Broker KafkaNodePool created with correct replicas | P0 |
| K-003 | kafka-cluster.yaml | Kafka CR has KRaft annotations | P0 |
| K-004 | kafka-cluster.yaml | 3 listeners: internal(9092), tls(9093), external(9094) | P0 |
| K-005 | kafka-cluster.yaml | Storage size from values | P0 |
| K-006 | kafka-cluster.yaml | Config values (retention, replication) from values | P1 |
| K-007 | kafka-cluster.yaml | Nothing rendered when `enabled=false` | P0 |
| K-008 | kafka-bridge.yaml | KafkaBridge CR rendered when `bridge.enabled=true` | P0 |
| K-009 | kafka-bridge.yaml | LoadBalancer Service for bridge | P1 |
| K-010 | kafka-bridge.yaml | Bridge NOT rendered when `bridge.enabled=false` | P0 |
| K-011 | kafka-topics.yaml | One KafkaTopic per entry in `.topics` | P0 |
| K-012 | kafka-topics.yaml | Partitions and replicas from values | P1 |
| K-013 | kafka-users.yaml | KafkaUser `kafkapump` with TLS auth | P0 |
| K-014 | kafka-users.yaml | ACLs include topic, cluster, group permissions | P1 |

### 2.3 VictoriaMetrics Sub-Chart Tests

| Test ID | Template | Assertion | Priority |
|---------|----------|-----------|----------|
| VM-001 | vmcluster.yaml | VMCluster rendered when `deploymentMode=cluster` | P0 |
| VM-002 | vmcluster.yaml | VMSingle rendered when `deploymentMode=single` | P0 |
| VM-003 | vmcluster.yaml | Retention period from values | P0 |
| VM-004 | vmcluster.yaml | vmstorage replicas, resources from values | P0 |
| VM-005 | vmcluster.yaml | TLS extraArgs when `tls.enabled=true` | P0 |
| VM-006 | vmcluster.yaml | TLS volumes and volumeMounts when enabled | P0 |
| VM-007 | vmcluster.yaml | Init container for lock file cleanup | P1 |
| VM-008 | vmcluster.yaml | Anti-affinity rules on all components | P1 |
| VM-009 | vmcluster.yaml | Nothing rendered when `enabled=false` | P0 |
| VM-010 | vmagent.yaml | VMAgent remoteWrite URL points to vminsert in cluster mode | P0 |
| VM-011 | vmagent.yaml | VMAgent remoteWrite URL points to vmsingle in single mode | P0 |
| VM-012 | vmagent.yaml | TLS CA reference in remoteWrite when TLS enabled | P1 |
| VM-013 | vmagent-rbac.yaml | SA, Role, RoleBinding, ClusterRole, CRB all created | P0 |
| VM-014 | vmagent-rbac.yaml | RBAC not created when `rbac.create=false` | P0 |
| VM-015 | vmscrape.yaml | VMPodScrape for iDRAC rendered | P1 |
| VM-016 | vlcluster.yaml | VLCluster rendered with vlstorage/vlinsert/vlselect | P0 |
| VM-017 | vlcluster.yaml | TLS config on all VL components | P0 |
| VM-018 | vlcluster.yaml | Nothing rendered when `logs.enabled=false` | P0 |
| VM-019 | vlagent.yaml | VLAgent with syslog listeners | P0 |
| VM-020 | vlagent.yaml | LoadBalancer service with NodePorts | P1 |
| VM-021 | vlagent.yaml | PVC storage size from values | P1 |

### 2.4 iDRAC Sub-Chart Tests

| Test ID | Template | Assertion | Priority |
|---------|----------|-----------|----------|
| ID-001 | statefulset.yaml | StatefulSet created with correct name | P0 |
| ID-002 | statefulset.yaml | MySQL container present with correct image | P0 |
| ID-003 | statefulset.yaml | ActiveMQ container present | P0 |
| ID-004 | statefulset.yaml | Receiver container present | P0 |
| ID-005 | statefulset.yaml | kafka-pump present when `collectionTargets.kafka=true` | P0 |
| ID-006 | statefulset.yaml | kafka-pump absent when `collectionTargets.kafka=false` | P0 |
| ID-007 | statefulset.yaml | victoria-pump present when `collectionTargets.victoriaMetrics=true` | P0 |
| ID-008 | statefulset.yaml | victoria-pump absent when `collectionTargets.victoriaMetrics=false` | P0 |
| ID-009 | statefulset.yaml | Kafka cert volumes mounted when kafka enabled | P1 |
| ID-010 | statefulset.yaml | Init container for MySQL lock cleanup | P1 |
| ID-011 | statefulset.yaml | Nothing rendered when `enabled=false` | P0 |
| ID-012 | secret.yaml | MySQL credentials Secret created | P0 |
| ID-013 | secret.yaml | Secret NOT created when `existingSecret` set | P0 |
| ID-014 | service.yaml | Headless Service created | P0 |
| ID-015 | statefulset.yaml | VolumeClaimTemplate with correct storage size | P1 |

### 2.5 LDMS Sub-Chart Tests

| Test ID | Template | Assertion | Priority |
|---------|----------|-----------|----------|
| LD-001 | statefulset-agg.yaml | Aggregator StatefulSet created | P0 |
| LD-002 | statefulset-store.yaml | Store StatefulSet created | P0 |
| LD-003 | statefulset-store.yaml | Kafka cert volumes mounted on store | P1 |
| LD-004 | secrets.yaml | OVIS auth Secret created | P0 |
| LD-005 | secrets.yaml | Munge key Secret created | P0 |
| LD-006 | secrets.yaml | Secrets NOT created when existingSecret set | P0 |
| LD-007 | service-agg.yaml | Aggregator headless Service | P0 |
| LD-008 | service-store.yaml | Store headless Service | P0 |
| LD-009 | * | Nothing rendered when `enabled=false` | P0 |

### 2.6 Vector Sub-Chart Tests

| Test ID | Template | Assertion | Priority |
|---------|----------|-----------|----------|
| VE-001 | vector-ldms-deployment.yaml | LDMS deployment rendered when enabled | P0 |
| VE-002 | vector-ldms-deployment.yaml | Security context (non-root, read-only FS) | P1 |
| VE-003 | vector-ldms-deployment.yaml | Kafka cert volumes mounted | P1 |
| VE-004 | vector-ldms-deployment.yaml | Not rendered when `ldms.enabled=false` | P0 |
| VE-005 | vector-ldms-configmap.yaml | TOML config with correct Kafka bootstrap | P0 |
| VE-006 | vector-ldms-configmap.yaml | Lua fan-out transform present | P1 |
| VE-007 | vector-ome-deployment.yaml | OME deployment rendered when enabled | P0 |
| VE-008 | vector-ome-deployment.yaml | Not rendered when `ome.enabled=false` | P0 |
| VE-009 | vector-ome-configmap.yaml | Topic router with metrics and logs routes | P0 |
| VE-010 | vector-ome-configmap.yaml | Only metrics route when logsEnabled=false | P1 |
| VE-011 | vector-ome-kafkauser.yaml | KafkaUser with prefix-based ACLs | P0 |
| VE-012 | vmagent-vector-deployment.yaml | Write-buffer deployment rendered | P0 |
| VE-013 | vmagent-vector-deployment.yaml | TLS CA mount when enabled | P1 |
| VE-014 | vlagent-vector-deployment.yaml | Log write-buffer deployment rendered | P0 |
| VE-015 | * | Nothing rendered when `enabled=false` | P0 |

### 2.7 External Sources Sub-Chart Tests

| Test ID | Template | Assertion | Priority |
|---------|----------|-----------|----------|
| ES-001 | ufm-external-service.yaml | UFM Service+Endpoints when enabled | P0 |
| ES-002 | ufm-external-service.yaml | Not rendered when `ufm.enabled=false` | P0 |
| ES-003 | ufm-secret.yaml | UFM Secret with basic auth credentials | P0 |
| ES-004 | ufm-vmscrape.yaml | VMServiceScrape with correct TLS mode | P0 |
| ES-005 | vast-external-service.yaml | VAST Service+Endpoints when enabled | P0 |
| ES-006 | vast-external-service.yaml | Not rendered when `vast.enabled=false` | P0 |
| ES-007 | vast-secret.yaml | VAST Secret with basic auth credentials | P0 |
| ES-008 | vast-vmscrape.yaml | VMServiceScrape with correct metrics path | P0 |
| ES-009 | powerscale-csi-exporter.yaml | CSI exporter Deployment+Service | P0 |
| ES-010 | powerscale-csi-exporter.yaml | Not rendered when disabled | P0 |

### 2.8 Telemetry Operator Sub-Chart Tests

| Test ID | Template | Assertion | Priority |
|---------|----------|-----------|----------|
| TO-001 | operator-deployment.yaml | Deployment created with correct replicas | P0 |
| TO-002 | operator-deployment.yaml | Leader election arg when enabled | P1 |
| TO-003 | operator-deployment.yaml | Security context (non-root, read-only FS) | P1 |
| TO-004 | operator-rbac.yaml | SA, ClusterRole, ClusterRoleBinding created | P0 |
| TO-005 | operator-rbac.yaml | CRD verbs include get/list/watch/update/patch | P1 |
| TO-006 | default-health-policy.yaml | Default TelemetryHealthPolicy CR | P0 |
| TO-007 | default-health-policy.yaml | 4 rules: 2 terminating + crashloop + pending | P0 |
| TO-008 | default-health-policy.yaml | Kafka rule has longer threshold (300s) | P1 |
| TO-009 | default-health-policy.yaml | Not rendered when `defaultPolicy.create=false` | P0 |
| TO-010 | * | Nothing rendered when `enabled=false` | P0 |

---

## 3. Render Validation Matrix

These test cases use `helm template` with different value combinations to
validate cross-chart behavior:

| Test ID | Configuration | Expected Resources | Validates |
|---------|---------------|-------------------|-----------|
| R-001 | All defaults | 61 resources | Full stack renders |
| R-002 | Only kafka+victoria-metrics | 27 resources | Minimal core |
| R-003 | `tls.enabled=false` | No TLS Job, no TLS volumes | TLS toggle |
| R-004 | `tls.existingSecret=my-secret` | No TLS Job | Existing secret path |
| R-005 | `victoria-metrics.metrics.deploymentMode=single` | VMSingle instead of VMCluster | Deployment mode |
| R-006 | `global.imageRegistry=registry.local:5000` | All images prefixed | Air-gap |
| R-007 | All sources disabled | Only sinks remain | Source toggles |
| R-008 | `kafka.bridge.enabled=false` | No KafkaBridge or LB Service | Bridge toggle |
| R-009 | UFM+VAST enabled with endpoints | External Services + Scrapes | External sources |
| R-010 | `victoria-metrics.logs.enabled=false` | No VLCluster, VLAgent | Logs toggle |

---

## 4. Integration Test Specification (Kind Cluster)

These tests require a running Kubernetes cluster with Strimzi and
VictoriaMetrics operators pre-installed.

| Test ID | Scenario | Steps | Expected Outcome |
|---------|----------|-------|------------------|
| I-001 | Full install | `helm install telemetry .` | All pods Running within 5 min |
| I-002 | Upgrade | Change retention, `helm upgrade` | Pods restart, new retention applied |
| I-003 | Rollback | `helm rollback telemetry 1` | Previous state restored |
| I-004 | Uninstall | `helm uninstall telemetry` | All resources cleaned up (PVCs remain) |
| I-005 | Helm tests | `helm test telemetry` | All test pods pass |
| I-006 | Minimal install | Disable ldms, vector, external | Only Kafka+VM+iDRAC pods |
| I-007 | Scale up | Increase vmstorage replicas to 5 | 5 vmstorage pods running |
| I-008 | TLS rotation | Regenerate certs, upgrade | New certs applied, pods restart |

---

## 5. Acceptance Criteria

### 5.1 Unit Tests
- All P0 tests pass
- All P1 tests pass
- Coverage: every template file has at least one test
- Coverage: every feature toggle tested (enabled/disabled)

### 5.2 Lint + Render
- `helm lint` passes with 0 errors
- `helm template` renders valid YAML for all matrix combinations
- No duplicate resource names within a namespace

### 5.3 Integration
- Full stack deploys successfully on Kind cluster
- `helm test` passes for all components
- `helm upgrade` and `helm rollback` work without data loss
