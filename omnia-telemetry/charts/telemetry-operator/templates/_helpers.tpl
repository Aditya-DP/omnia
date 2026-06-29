{{- define "telemetry-operator.namespace" -}}
{{- default "telemetry" .Values.global.namespace }}
{{- end }}

{{- define "telemetry-operator.labels" -}}
app.kubernetes.io/part-of: omnia-telemetry
app.kubernetes.io/component: telemetry-operator
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "telemetry-operator.image" -}}
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

{{- define "telemetry-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- .Values.serviceAccount.name | default "telemetry-operator" -}}
{{- else -}}
{{- .Values.serviceAccount.name | default "default" -}}
{{- end -}}
{{- end }}
