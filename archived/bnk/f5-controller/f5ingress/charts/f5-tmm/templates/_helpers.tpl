{{/*
Expand the name of the chart.
*/}}
{{- define "tmm.name" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Expand tmm service name.
*/}}
{{- define "tmm.serviceName" -}}
{{- default (include "tmm.name" .) .Values.tmm.service.name }}
{{- end -}}

{{/*
Create tmm labels
*/}}
{{- define "tmm.labels" -}}
app.kubernetes.io/name: {{ include "tmm.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Expand tmm app name.
*/}}
{{- define "tmm.appName" -}}
{{- default (include "tmm.name" .) .Values.tmm.name -}}
{{- end -}}

{{/*
Create the name of the service account
*/}}
{{- define "tmm.serviceAccountName" -}}
{{- if .Values.tmm.serviceAccount.create -}}
    {{ default (include "tmm.name" .) .Values.tmm.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.tmm.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{- define "enableObserver" -}}
{{- and (or (not (index .Values "f5-toda-logging" "enabled" | default false))
            (not (index .Values "f5-toda-logging" "tmstats" "enabled" | default false)))
            (index .Values "observer" "enabled" | default false) -}}
{{- end -}}
