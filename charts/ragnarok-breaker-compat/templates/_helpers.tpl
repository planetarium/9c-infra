{{- define "compat.labels" -}}
app: compat-server
app.kubernetes.io/name: compat-server
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: compat-server
{{- end }}

{{- define "compat.selectorLabels" -}}
app: compat-server
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
