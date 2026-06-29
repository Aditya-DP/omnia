# Omnia Telemetry Helm Chart Redesign - Document Index

| # | Document | Description | Status |
|---|----------|-------------|--------|
| 01 | [Engineering Spec (HLD)](./01-Engineering-Spec-HLD.md) | High-level architecture, Helm chart structure, deployment flow, CRD/operator design | Draft |
| 02 | [Component Spec](./02-Component-Spec.md) | Detailed design for each sub-chart, CRD definitions, operator controllers, values.yaml schema | Draft |
| 03 | [Implementation Plan](./03-Implementation-Plan.md) | Phased migration roadmap, backward compatibility strategy, testing plan | Draft |

## Context

The current Omnia telemetry deployment is driven by Ansible playbooks that generate
cloud-init files and Kubernetes manifests. A monolithic kustomize configuration
orchestrates all downstream manifests and Helm charts. Pod health is managed by a
primitive CronJob that deletes stuck pods every 3 minutes.

This redesign introduces a top-level Helm umbrella chart that orchestrates the
entire telemetry stack, with child charts for each component. Custom resources and
controllers replace ad-hoc CronJobs for health monitoring and remediation.

## Scope

- **In scope**: Helm chart architecture, values.yaml schema, child chart design,
  TelemetryHealth CRD/operator, deployment ordering, TLS management, upgrade strategy
- **Out of scope**: Ansible playbook refactoring (integration layer only),
  application-level telemetry logic changes, new telemetry source additions
