{{/* Define the "stats-collector.clusterRoleName" template */}}
{{- define "stats-collector.clusterRoleName" -}}
{{- printf "%s-%s-%s" .Release.Name "stats-collector" .Release.Namespace | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Define the "stats-collector.name" template */}}
{{- define "stats-collector.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Define the "stats-collector.labels" template */}}
{{- define "stats-collector.labels" -}}
app.kubernetes.io/name: {{ include "stats-collector.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Create the name of the service account
*/}}
{{- define "stats-collector.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "stats-collector.name" . | lower | replace "_" "-") .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}


