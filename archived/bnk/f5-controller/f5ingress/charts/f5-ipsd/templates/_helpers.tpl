{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
*/}}
{{- define "ipsd.name" -}}
{{- printf "%s" .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the name of the service account
*/}}
{{- define "ipsd.serviceAccountName" -}}
{{- if .Values.ipsd.serviceAccount.create -}}
    {{ default (include "ipsd.name" .) .Values.ipsd.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.ipsd.serviceAccount.name }}
{{- end -}}
{{- end -}}

