{{/*
Kafka chart helpers.
*/}}
{{- define "kafka.namespace" -}}
{{- default "telemetry" .Values.global.namespace }}
{{- end }}

{{- define "kafka.labels" -}}
app.kubernetes.io/part-of: omnia-telemetry
app.kubernetes.io/component: kafka
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "kafka.image" -}}
{{- $img := .image -}}
{{- if and .global .global.imageRegistry -}}
{{- $parts := splitList "/" $img -}}
{{- if gt (len $parts) 1 -}}
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
