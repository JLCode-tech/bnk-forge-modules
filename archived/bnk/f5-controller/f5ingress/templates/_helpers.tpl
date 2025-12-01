{{/* vim: set filetype=mustache: */}}

{{/*
Expand the name of the chart.
*/}}
{{- define "f5ingress.name" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create labels
*/}}
{{- define "f5ingress.labels" -}}
app.kubernetes.io/name: {{ include "f5ingress.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Expand the name of the configmap.
*/}}
{{- define "f5ingress.configName" -}}
{{- default (include "f5ingress.name" .) .Values.controller.config.name -}}
{{- end -}}

{{/*
Expand cluster role and cluster role binding name.
*/}}
{{- define "f5ingress.roleName" -}}
{{- printf "%s-%s-%s" .Release.Name .Chart.Name .Release.Namespace | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Expand OTEL cluster role and OTEL cluster role binding name.
*/}}
{{- define "f5ingress.otel.clusterRoleName" -}}
{{- printf "%s-%s-%s-%s" .Release.Name .Chart.Name "otel" .Release.Namespace | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Expand service name.
*/}}
{{- define "f5ingress.serviceName" -}}
{{- default (include "f5ingress.name" .) .Values.controller.debug.aid.serviceName }}
{{- end -}}


{{/*
Expand service account name.
*/}}
{{- define "f5ingress.serviceAccountName" -}}
{{- default (include "f5ingress.name" .) .Values.controller.serviceAccount.name -}}
{{- end -}}


{{/*
Expand app name.
*/}}
{{- define "f5ingress.appName" -}}
{{- default (include "f5ingress.name" .) .Values.controller.name -}}
{{- end -}}

{{/*
Get type of watchNamespace input
*/}}
{{- define "f5ingress.watchNamespaceType" -}}
{{- if .Values.controller.watchNamespace -}}
{{- printf "%T" .Values.controller.watchNamespace }}
{{- end -}}
{{- end -}}

{{- define "f5ingress.watchAllNamespaces" -}}
{{- if eq (include "f5ingress.watchNamespaceType" .) "string" -}}
{{- if eq  .Values.controller.watchNamespace "All" -}}
{{- true -}}
{{- else -}}
{{- false -}}
{{- end -}}
{{- else if eq (include "f5ingress.watchNamespaceType" .) "[]interface {}" -}}
{{ $enabled := false }}
{{- range .Values.controller.watchNamespace }}
{{- if eq . "All" -}}
{{- $enabled = true -}}
{{- end -}}
{{- end -}}
{{- $enabled -}}
{{- end -}}
{{- end }}


{{/*
Convert watchNamespace to string
*/}}
{{- define "f5ingress.watchNamespaceString" -}}
{{- if eq (include "f5ingress.watchNamespaceType" .) "string" -}}
{{- .Values.controller.watchNamespace -}}
{{- else if eq (include "f5ingress.watchNamespaceType" .) "[]interface {}" -}}
{{ $myList := list }}
{{- range .Values.controller.watchNamespace }}
{{- $myList = append $myList . -}}
{{- end -}}
{{- $myList | join "," -}}
{{- end -}}
{{- end }}


{{/*
Create the name of the service account for dnsx to use
*/}}
{{- define "dnsx.serviceAccountName" -}}
{{- if .Values.dnsx.serviceAccount.create -}}
    {{ default .Values.dnsx.name .Values.dnsx.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.dnsx.serviceAccount.name }}
{{- end -}}
{{- end -}}

