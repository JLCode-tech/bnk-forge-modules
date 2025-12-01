{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
*/}}
{{- define "afm.name" -}}
{{- printf "%s" .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create the name of the service account
*/}}
{{- define "afm.serviceAccountName" -}}
{{- if .Values.afm.serviceAccount.create -}}
    {{ default (include "afm.name" .) .Values.afm.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.afm.serviceAccount.name }}
{{- end -}}
{{- end -}}

