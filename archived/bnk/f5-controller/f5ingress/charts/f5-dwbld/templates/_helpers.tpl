{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
*/}}
{{- define "dwbld.name" -}}
{{- printf "%s" .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the name of the service account
*/}}
{{- define "dwbld.serviceAccountName" -}}
{{- if .Values.dwbld.serviceAccount.create -}}
    {{ default (include "dwbld.name" .) .Values.dwbld.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.dwbld.serviceAccount.name }}
{{- end -}}
{{- end -}}
