{{- define "cneproxy.name" -}}
{{- $name := default .Chart.Name -}}
{{- printf "%s" $name -}}
{{- end -}}

{{- define "cneproxy.rbacname" -}}
{{- printf "mbip-ve-%s-%s" .Release.Namespace .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cneproxy.bindingname" -}}
{{- printf "mbip-ve-%s-%s" .Release.Namespace .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cneproxy.servicename" -}}
{{- printf "%s" (include "cneproxy.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cneproxy.saname" -}}
{{- printf "mbip-ve-%s-%s" .Release.Namespace .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "common.tenantPrefix" }}
{{- if  .Values.global  }}
{{- if  .Values.global.setPrefix  }}
{{- printf "%s-" .Release.Name }}
{{- else }}
{{- printf "" }}
{{- end }}
{{- end}}
{{- end }}
