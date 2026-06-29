{{- define "external-sources.namespace" -}}
{{- default "telemetry" .Values.global.namespace }}
{{- end }}

{{- define "external-sources.labels" -}}
app.kubernetes.io/part-of: omnia-telemetry
app.kubernetes.io/component: external-sources
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "external-sources.image" -}}
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

{{- define "external-sources.ufmSecretName" -}}
{{- if .Values.ufm.credentials.existingSecret -}}
{{- .Values.ufm.credentials.existingSecret -}}
{{- else -}}
ufm-telemetry-credentials
{{- end -}}
{{- end }}

{{- define "external-sources.vastSecretName" -}}
{{- if .Values.vast.credentials.existingSecret -}}
{{- .Values.vast.credentials.existingSecret -}}
{{- else -}}
vast-telemetry-credentials
{{- end -}}
{{- end }}
