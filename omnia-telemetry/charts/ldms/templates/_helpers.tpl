{{- define "ldms.namespace" -}}
{{- default "telemetry" .Values.global.namespace }}
{{- end }}

{{- define "ldms.labels" -}}
app.kubernetes.io/part-of: omnia-telemetry
app.kubernetes.io/component: ldms
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "ldms.image" -}}
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

{{- define "ldms.ovisSecretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- .Values.auth.existingSecret -}}
{{- else -}}
ldms-ovis-auth
{{- end -}}
{{- end }}

{{- define "ldms.mungeSecretName" -}}
{{- if .Values.munge.existingSecret -}}
{{- .Values.munge.existingSecret -}}
{{- else -}}
ldms-munge-key
{{- end -}}
{{- end }}
