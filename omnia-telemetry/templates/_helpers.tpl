{{/*
Expand the name of the chart.
*/}}
{{- define "omnia-telemetry.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name (release-qualified).
*/}}
{{- define "omnia-telemetry.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Target namespace.
*/}}
{{- define "omnia-telemetry.namespace" -}}
{{- default "telemetry" .Values.global.namespace }}
{{- end }}

{{/*
Standard labels for all resources.
*/}}
{{- define "omnia-telemetry.labels" -}}
helm.sh/chart: {{ include "omnia-telemetry.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: omnia-telemetry
{{ include "omnia-telemetry.selectorLabels" . }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "omnia-telemetry.selectorLabels" -}}
app.kubernetes.io/name: {{ include "omnia-telemetry.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Chart name and version for chart label.
*/}}
{{- define "omnia-telemetry.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Build a full image reference, applying global registry override.
Usage: {{ include "omnia-telemetry.image" (dict "image" "victoriametrics/vmagent:v1.128.0" "global" .Values.global) }}
*/}}
{{- define "omnia-telemetry.image" -}}
{{- $img := .image -}}
{{- if and .global .global.imageRegistry -}}
{{- $parts := splitList "/" $img -}}
{{- if gt (len $parts) 1 -}}
{{/* Strip existing registry prefix (first segment with a dot or colon) */}}
{{- $first := index $parts 0 -}}
{{- if or (contains "." $first) (contains ":" $first) -}}
{{- $rest := join "/" (rest $parts) -}}
{{- printf "%s/%s" .global.imageRegistry $rest -}}
{{- else -}}
{{- printf "%s/%s" .global.imageRegistry $img -}}
{{- end -}}
{{- else -}}
{{- printf "%s/%s" .global.imageRegistry $img -}}
{{- end -}}
{{- else -}}
{{- $img -}}
{{- end -}}
{{- end }}

{{/*
TLS secret name for Victoria components.
*/}}
{{- define "omnia-telemetry.tlsSecretName" -}}
{{- if .Values.tls.existingSecret -}}
{{- .Values.tls.existingSecret -}}
{{- else -}}
{{- printf "%s-tls" (include "omnia-telemetry.fullname" .) -}}
{{- end -}}
{{- end }}

{{/*
Determine if Kafka is required based on sources and bridges.
Returns "true" or "".
*/}}
{{- define "omnia-telemetry.kafkaRequired" -}}
{{- if .Values.kafka.enabled -}}
  {{- if or
    (and .Values.sources.idrac.enabled (has "kafka" .Values.sources.idrac.collectionTargets))
    (and .Values.sources.ldms.enabled (has "kafka" .Values.sources.ldms.collectionTargets))
    (and (or .Values.sources.ome.metricsEnabled .Values.sources.ome.logsEnabled) (has "kafka" .Values.sources.ome.collectionTargets))
    .Values.bridges.vectorLdms.enabled
    (or .Values.bridges.vectorOme.metricsEnabled .Values.bridges.vectorOme.logsEnabled)
  -}}true{{- end -}}
{{- end -}}
{{- end }}

{{/*
Determine if VictoriaMetrics is required based on sources and bridges.
*/}}
{{- define "omnia-telemetry.victoriaMetricsRequired" -}}
{{- $vm := index .Values "victoria-metrics" -}}
{{- if $vm.enabled -}}
  {{- if or
    (and .Values.sources.idrac.enabled (has "victoria_metrics" .Values.sources.idrac.collectionTargets))
    (and .Values.sources.powerscale.metricsEnabled (has "victoria_metrics" .Values.sources.powerscale.collectionTargets))
    (and .Values.sources.ufm.metricsEnabled (has "victoria_metrics" .Values.sources.ufm.collectionTargets))
    (and .Values.sources.vast.metricsEnabled (has "victoria_metrics" .Values.sources.vast.collectionTargets))
    .Values.bridges.vectorLdms.enabled
    .Values.bridges.vectorOme.metricsEnabled
  -}}true{{- end -}}
{{- end -}}
{{- end }}

{{/*
Determine if VictoriaLogs is required based on sources and bridges.
*/}}
{{- define "omnia-telemetry.victoriaLogsRequired" -}}
{{- $vm := index .Values "victoria-metrics" -}}
{{- if $vm.enabled -}}
  {{- if or
    (and .Values.sources.powerscale.logsEnabled (has "victoria_logs" .Values.sources.powerscale.collectionTargets))
    (and .Values.sources.ufm.logsEnabled (has "victoria_logs" .Values.sources.ufm.collectionTargets))
    (and .Values.sources.vast.logsEnabled (has "victoria_logs" .Values.sources.vast.collectionTargets))
    .Values.bridges.vectorOme.logsEnabled
  -}}true{{- end -}}
{{- end -}}
{{- end }}

{{/*
Kafka bootstrap servers (internal FQDN within the telemetry namespace).
*/}}
{{- define "omnia-telemetry.kafkaBootstrapServers" -}}
kafka-kafka-bootstrap.{{ include "omnia-telemetry.namespace" . }}.svc:9093
{{- end }}

{{/*
VMInsert URL for remote write.
*/}}
{{- define "omnia-telemetry.vminsertURL" -}}
{{- $vm := index .Values "victoria-metrics" -}}
{{- if eq $vm.metrics.deploymentMode "cluster" -}}
https://vminsert-victoria-cluster.{{ include "omnia-telemetry.namespace" . }}.svc:8480/insert/0/prometheus/api/v1/write
{{- else -}}
https://victoria-single.{{ include "omnia-telemetry.namespace" . }}.svc:8428/api/v1/write
{{- end -}}
{{- end }}

{{/*
VLInsert URL for log remote write.
*/}}
{{- define "omnia-telemetry.vlinsertURL" -}}
http://vlinsert-victoria-logs.{{ include "omnia-telemetry.namespace" . }}.svc:9481/insert/jsonline
{{- end }}
