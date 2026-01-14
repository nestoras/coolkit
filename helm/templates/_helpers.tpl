{{- define "coolkit.name" -}}
coolkit
{{- end -}}

{{- define "coolkit.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "coolkit.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "coolkit.labels" -}}
app.kubernetes.io/name: {{ include "coolkit.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: Helm
{{- end -}}
