{{- define "victoria-metrics.namespace" -}}
{{- default "telemetry" .Values.global.namespace }}
{{- end }}

{{- define "victoria-metrics.labels" -}}
app.kubernetes.io/part-of: omnia-telemetry
app.kubernetes.io/component: victoria-metrics
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "victoria-metrics.image" -}}
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

{{- define "victoria-metrics.tlsSecretName" -}}
{{- default "victoria-tls-certs" .Values.tls.secretName }}
{{- end }}
