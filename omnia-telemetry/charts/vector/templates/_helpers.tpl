{{- define "vector.namespace" -}}
{{- default "telemetry" .Values.global.namespace }}
{{- end }}

{{- define "vector.labels" -}}
app.kubernetes.io/part-of: omnia-telemetry
app.kubernetes.io/component: vector
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "vector.image" -}}
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

{{- define "vector.tlsSecretName" -}}
{{- default "victoria-tls-certs" .Values.tls.secretName }}
{{- end }}

{{- define "vector.vminsertURL" -}}
https://vminsert-victoria-cluster.{{ include "vector.namespace" . }}.svc:8480/insert/0/prometheus/api/v1/write
{{- end }}

{{- define "vector.vlinsertURL" -}}
http://vlinsert-victoria-logs-cluster.{{ include "vector.namespace" . }}.svc:9481/insert/jsonline
{{- end }}
