# Testing Guide - Omnia Telemetry Helm Chart

This guide explains how to run and maintain tests for the Omnia Telemetry Helm Chart.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Unit Testing](#unit-testing)
4. [Render Validation](#render-validation)
5. [Lint Validation](#lint-validation)
6. [Integration Testing](#integration-testing)
7. [Writing New Tests](#writing-new-tests)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

1. **Helm 3.x**
   ```bash
   helm version
   # Should show v3.x.x
   ```

2. **helm-unittest plugin**
   ```bash
   # Install (if not already installed)
   helm plugin install https://github.com/helm-unittest/helm-unittest.git
   
   # Verify installation
   helm unittest --help
   ```

3. **kubectl** (for integration tests)
   ```bash
   kubectl version --client
   ```

4. **Kind** (optional, for local integration tests)
   ```bash
   kind version
   ```

---

## Quick Start

Run all tests with a single command:

```bash
cd omnia-telemetry
helm unittest .
```

Expected output:
```
Charts:      1 passed, 1 total
Test Suites: 8 passed, 8 total
Tests:       165 passed, 165 total
Time:        ~4-5 seconds
```

---

## Unit Testing

### Run All Unit Tests

```bash
cd omnia-telemetry
helm unittest .
```

### Run Tests for Specific Component

```bash
# Umbrella chart only
helm unittest . -f 'tests/umbrella_test.yaml'

# Kafka sub-chart only
helm unittest . -f 'charts/kafka/tests/kafka_test.yaml'

# VictoriaMetrics sub-chart only
helm unittest . -f 'charts/victoria-metrics/tests/victoria_metrics_test.yaml'

# iDRAC sub-chart only
helm unittest . -f 'charts/idrac/tests/idrac_test.yaml'

# LDMS sub-chart only
helm unittest . -f 'charts/ldms/tests/ldms_test.yaml'

# Vector sub-chart only
helm unittest . -f 'charts/vector/tests/vector_test.yaml'

# External Sources sub-chart only
helm unittest . -f 'charts/external-sources/tests/external_sources_test.yaml'

# Telemetry Operator sub-chart only
helm unittest . -f 'charts/telemetry-operator/tests/operator_test.yaml'
```

### Run Tests with Verbose Output

```bash
helm unittest . --output-type junit
```

### Run Tests with Detailed Failure Information

```bash
helm unittest . --output-type tap
```

### Run Tests with Summary Only

```bash
helm unittest . --output-type summary
```

---

## Render Validation

### Test Matrix Scenarios

These commands validate the render validation matrix from the Test Spec:

#### R-001: All Defaults (61 resources)

```bash
cd omnia-telemetry
helm template test-release . | grep -c '^kind:'
# Expected: 61
```

#### R-002: Minimal Core - Only Kafka + VictoriaMetrics (27 resources)

```bash
helm template test-release . \
  --set idrac.enabled=false \
  --set ldms.enabled=false \
  --set vector.enabled=false \
  --set external-sources.enabled=false \
  --set telemetry-operator.enabled=false | grep -c '^kind:'
# Expected: 27
```

#### R-003: TLS Disabled (No TLS Job)

```bash
helm template test-release . --set tls.enabled=false | grep -E '(kind: Job|name: tls-cert-job)' | wc -l
# Expected: 0
```

#### R-004: Existing TLS Secret (No TLS Job)

```bash
helm template test-release . --set tls.existingSecret=my-tls-secret | grep -E '(kind: Job|name: tls-cert-job)' | wc -l
# Expected: 0
```

#### R-005: Single-Node VictoriaMetrics (VMSingle)

```bash
helm template test-release . --set victoria-metrics.metrics.deploymentMode=single | grep -E 'kind: (VMSingle|VMCluster)'
# Expected: kind: VMSingle
```

#### R-006: Air-Gap Registry (All Images Prefixed)

```bash
helm template test-release . --set global.imageRegistry=registry.local:5000 | grep 'image:' | head -5
# Expected: All images start with registry.local:5000/
```

#### R-007: All Sources Disabled (Only Sinks)

```bash
helm template test-release . \
  --set idrac.enabled=false \
  --set ldms.enabled=false \
  --set vector.enabled=false \
  --set external-sources.enabled=false | grep -c '^kind:'
# Expected: ~30 (Kafka + VictoriaMetrics + Operator)
```

#### R-008: Kafka Bridge Disabled (No KafkaBridge)

```bash
helm template test-release . --set kafka.bridge.enabled=false | grep 'kind: KafkaBridge' | wc -l
# Expected: 0
```

#### R-009: External Sources Enabled (UFM + VAST)

```bash
helm template test-release . \
  --set external-sources.ufm.enabled=true \
  --set external-sources.ufm.endpoints[0].ip=10.0.0.1 \
  --set external-sources.vast.enabled=true \
  --set external-sources.vast.endpoints[0].ip=10.0.0.2 | grep -E 'kind: (Service|VMServiceScrape)' | wc -l
# Expected: Multiple Services and VMServiceScrapes
```

#### R-010: Logs Disabled (No VLCluster)

```bash
helm template test-release . --set victoria-metrics.logs.enabled=false | grep 'kind: VLCluster' | wc -l
# Expected: 0
```

### Full Render Validation Script

Save this as `scripts/validate-renders.sh`:

```bash
#!/bin/bash
set -e

CHART_DIR="omnia-telemetry"
FAILED=0

echo "=== Render Validation Matrix ==="
echo

# R-001
echo "R-001: All defaults..."
COUNT=$(helm template test-release $CHART_DIR | grep -c '^kind:')
if [ "$COUNT" -eq 61 ]; then
  echo "✅ PASS: 61 resources"
else
  echo "❌ FAIL: Expected 61, got $COUNT"
  FAILED=$((FAILED+1))
fi

# R-002
echo "R-002: Minimal core..."
COUNT=$(helm template test-release $CHART_DIR \
  --set idrac.enabled=false \
  --set ldms.enabled=false \
  --set vector.enabled=false \
  --set external-sources.enabled=false \
  --set telemetry-operator.enabled=false | grep -c '^kind:')
if [ "$COUNT" -eq 27 ]; then
  echo "✅ PASS: 27 resources"
else
  echo "❌ FAIL: Expected 27, got $COUNT"
  FAILED=$((FAILED+1))
fi

# R-003
echo "R-003: TLS disabled..."
COUNT=$(helm template test-release $CHART_DIR --set tls.enabled=false | grep -E '(kind: Job|name: tls-cert-job)' | wc -l)
if [ "$COUNT" -eq 0 ]; then
  echo "✅ PASS: No TLS Job"
else
  echo "❌ FAIL: TLS Job found"
  FAILED=$((FAILED+1))
fi

# R-004
echo "R-004: Existing TLS secret..."
COUNT=$(helm template test-release $CHART_DIR --set tls.existingSecret=my-tls-secret | grep -E '(kind: Job|name: tls-cert-job)' | wc -l)
if [ "$COUNT" -eq 0 ]; then
  echo "✅ PASS: No TLS Job"
else
  echo "❌ FAIL: TLS Job found"
  FAILED=$((FAILED+1))
fi

# R-005
echo "R-005: Single-node Victoria..."
OUTPUT=$(helm template test-release $CHART_DIR --set victoria-metrics.metrics.deploymentMode=single | grep -E 'kind: (VMSingle|VMCluster)')
if echo "$OUTPUT" | grep -q "kind: VMSingle"; then
  echo "✅ PASS: VMSingle rendered"
else
  echo "❌ FAIL: VMSingle not found"
  FAILED=$((FAILED+1))
fi

# R-006
echo "R-006: Air-gap registry..."
OUTPUT=$(helm template test-release $CHART_DIR --set global.imageRegistry=registry.local:5000 | grep 'image:' | head -1)
if echo "$OUTPUT" | grep -q "registry.local:5000"; then
  echo "✅ PASS: Images prefixed"
else
  echo "❌ FAIL: Images not prefixed"
  FAILED=$((FAILED+1))
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "✅ All render validation tests passed"
  exit 0
else
  echo "❌ $FAILED render validation tests failed"
  exit 1
fi
```

Run it:
```bash
chmod +x scripts/validate-renders.sh
./scripts/validate-renders.sh
```

---

## Lint Validation

### Run Helm Lint

```bash
cd omnia-telemetry
helm lint .
```

Expected output:
```
==> Linting .
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

### Lint with Custom Values

```bash
helm lint . --values custom-values.yaml
```

### Strict Lint (Fail on Warnings)

```bash
helm lint . --strict
```

---

## Integration Testing

### Prerequisites

1. **Kind cluster with operators**:
   ```bash
   # Create Kind cluster
   kind create cluster --name telemetry-test
   
   # Install Strimzi operator
   kubectl create namespace kafka
   kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
   
   # Install VictoriaMetrics operator
   helm repo add vm https://victoriametrics.github.io/helm-charts/
   helm repo update
   helm install vm-operator vm/victoria-metrics-operator -n vm-system --create-namespace
   
   # Wait for operators to be ready
   kubectl wait --for=condition=ready pod -l name=strimzi-cluster-operator -n kafka --timeout=300s
   kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=victoria-metrics-operator -n vm-system --timeout=300s
   ```

### I-001: Full Install

```bash
cd omnia-telemetry
helm install telemetry . --create-namespace --namespace telemetry

# Wait for all pods to be ready (may take 5 minutes)
kubectl wait --for=condition=ready pod --all -n telemetry --timeout=600s

# Check status
kubectl get pods -n telemetry
```

### I-002: Upgrade

```bash
# Change retention period
helm upgrade telemetry . --namespace telemetry \
  --set victoria-metrics.metrics.retentionPeriod=30d

# Verify pods restart
kubectl get pods -n telemetry -w
```

### I-003: Rollback

```bash
# Rollback to previous version
helm rollback telemetry 1 --namespace telemetry

# Verify rollback
helm history telemetry --namespace telemetry
```

### I-004: Uninstall

```bash
# Uninstall chart
helm uninstall telemetry --namespace telemetry

# Verify cleanup (PVCs should remain)
kubectl get all,pvc -n telemetry
```

### I-005: Helm Tests

```bash
# Install chart with test hooks
helm install telemetry . --namespace telemetry

# Run tests
helm test telemetry --namespace telemetry

# Check test results
kubectl logs -n telemetry -l helm.sh/chart=omnia-telemetry
```

### I-006: Minimal Install

```bash
helm install telemetry . --namespace telemetry \
  --set idrac.enabled=false \
  --set ldms.enabled=false \
  --set vector.enabled=false \
  --set external-sources.enabled=false

# Verify only Kafka + VM + Operator pods
kubectl get pods -n telemetry
```

### I-007: Scale Up

```bash
# Scale vmstorage to 5 replicas
helm upgrade telemetry . --namespace telemetry \
  --set victoria-metrics.metrics.vmstorage.replicaCount=5

# Verify 5 vmstorage pods
kubectl get pods -n telemetry -l app.kubernetes.io/component=vmstorage
```

### I-008: TLS Rotation

```bash
# Delete existing TLS secret
kubectl delete secret telemetry-tls -n telemetry

# Regenerate certs by upgrading
helm upgrade telemetry . --namespace telemetry --force

# Verify new certs applied
kubectl get secret telemetry-tls -n telemetry -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

---

## Writing New Tests

### Test Structure

Each test file follows this structure:

```yaml
suite: <Component> Sub-Chart Tests
templates:
  - <template-file-1.yaml>
  - <template-file-2.yaml>
tests:
  - it: <Test ID>: <Description>
    template: <template-file.yaml>
    set:
      <key>: <value>
    asserts:
      - <assertion-type>:
          path: <yaml-path>
          value: <expected-value>
```

### Common Assertions

```yaml
# Check if a value equals expected
- equal:
    path: metadata.name
    value: my-resource

# Check if a value matches regex
- matchRegex:
    path: spec.image
    pattern: ^registry\.local:5000/

# Check if a list contains an item
- contains:
    path: spec.containers
    content:
      name: my-container

# Check if a list does NOT contain an item
- notContains:
    path: spec.volumes
    content:
      name: kafka-certs

# Check if a value is null
- isNull:
    path: spec.tls

# Check if a value is NOT null
- isNotNull:
    path: spec.tls

# Check if a resource exists
- hasDocuments:
    count: 1

# Check if no resources rendered
- hasDocuments:
    count: 0
```

### Example: Adding a New Test

Let's add a test for a new Kafka topic:

1. **Edit** `charts/kafka/tests/kafka_test.yaml`:

```yaml
  - it: K-015 New topic 'my-new-topic' created with correct partitions
    template: kafka-topics.yaml
    set:
      topics:
        - name: my-new-topic
          partitions: 10
          replicas: 3
    asserts:
      - hasDocuments:
          count: 1
      - equal:
          path: metadata.name
          value: my-new-topic
      - equal:
          path: spec.partitions
          value: 10
      - equal:
          path: spec.replicas
          value: 3
```

2. **Run the test**:

```bash
helm unittest . -f 'charts/kafka/tests/kafka_test.yaml'
```

3. **Update Test Spec**: Add K-015 to `docs/telemetry-helm-redesign/04-Test-Spec.md`

---

## Troubleshooting

### Test Failures

#### "template not exists" Error

**Cause**: Template is gated by a condition and the condition is false.

**Solution**: Check that the template's conditional logic matches your test's `set` values.

```yaml
# If template has:
{{- if .Values.enabled }}
...
{{- end }}

# Your test must have:
set:
  enabled: true
```

#### "path not found" Error

**Cause**: The YAML path in your assertion doesn't exist in the rendered template.

**Solution**: 
1. Render the template manually to see its structure:
   ```bash
   helm template test-release . --show-only charts/kafka/templates/kafka-cluster.yaml
   ```
2. Update the path in your assertion to match the actual structure.

#### Float Comparison Failures

**Cause**: Large integers may be rendered in scientific notation (e.g., `6.048e+08`).

**Solution**: Use regex matching instead of exact equality:

```yaml
# Instead of:
- equal:
    path: spec.config.log\.retention\.ms
    value: 604800000

# Use:
- matchRegex:
    path: spec.config.log\.retention\.ms
    pattern: ^(604800000|6\.048e\+08)$
```

### Render Validation Failures

#### Resource Count Mismatch

**Cause**: Chart structure changed or dependencies updated.

**Solution**:
1. Render the chart and count resources manually:
   ```bash
   helm template test-release . | grep -c '^kind:'
   ```
2. Update the expected count in the Test Spec and validation scripts.

#### Image Prefix Not Applied

**Cause**: Some templates may not use the `global.imageRegistry` value.

**Solution**: Check all templates use the image helper:

```yaml
# Correct:
image: {{ include "omnia-telemetry.image" (dict "registry" .Values.global.imageRegistry "repository" "myimage" "tag" "1.0") }}

# Incorrect:
image: myregistry/myimage:1.0
```

---

## CI/CD Integration

### GitHub Actions Example

Create `.github/workflows/helm-test.yml`:

```yaml
name: Helm Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install Helm
        uses: azure/setup-helm@v3
        with:
          version: '3.12.0'
      
      - name: Install helm-unittest
        run: helm plugin install https://github.com/helm-unittest/helm-unittest.git
      
      - name: Run unit tests
        run: |
          cd omnia-telemetry
          helm unittest .
      
      - name: Run lint
        run: |
          cd omnia-telemetry
          helm lint .
      
      - name: Validate renders
        run: |
          cd omnia-telemetry
          ./scripts/validate-renders.sh
```

### GitLab CI Example

Create `.gitlab-ci.yml`:

```yaml
stages:
  - test

helm-test:
  stage: test
  image: alpine/helm:3.12.0
  before_script:
    - helm plugin install https://github.com/helm-unittest/helm-unittest.git
  script:
    - cd omnia-telemetry
    - helm unittest .
    - helm lint .
    - ./scripts/validate-renders.sh
  only:
    - main
    - develop
    - merge_requests
```

---

## Additional Resources

- [helm-unittest Documentation](https://github.com/helm-unittest/helm-unittest)
- [Helm Testing Guide](https://helm.sh/docs/topics/chart_tests/)
- [Test Specification](./04-Test-Spec.md)
- [Validation Report](./05-Validation-Report.md)
- [Engineering Spec (HLD)](./01-Engineering-Spec-HLD.md)

---

**Last Updated**: 2026-06-30  
**Maintainer**: Omnia Telemetry Team
