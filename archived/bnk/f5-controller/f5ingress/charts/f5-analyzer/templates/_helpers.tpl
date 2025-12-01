{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
*/}}
{{- define "f5Analyzer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "f5Analyzer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create the name of the service account
*/}}
{{- define "analyzer.serviceAccountName" -}}
{{- if .Values.analyzer.serviceAccount.create -}}
    {{ default (include "f5Analyzer.name" .) .Values.analyzer.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.analyzer.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Expand cluster role and cluster role binding name.
*/}}
{{- define "analyzer.roleName" -}}
{{- printf "%s-%s-%s" .Release.Name .Chart.Name .Release.Namespace | trunc 63 | trimSuffix "-" -}}
{{- end -}}
