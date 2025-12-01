{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
*/}}
{{- define "downloader.name" -}}
{{- printf "%s" .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the name of the service account
*/}}
{{- define "downloader.serviceAccountName" -}}
{{- if .Values.downloader.serviceAccount.create -}}
    {{ default (include "downloader.name" .) .Values.downloader.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.downloader.serviceAccount.name }}
{{- end -}}
{{- end -}}
