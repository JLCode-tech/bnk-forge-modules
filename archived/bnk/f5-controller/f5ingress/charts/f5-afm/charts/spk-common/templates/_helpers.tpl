{{/*
Common environment variables that are injected into each container
*/}}
{{- define "env.spk" -}}
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
{{- if .cName }}      
- name: CONTAINER_NAME
  value: {{ .cName }}
{{- end }}  
{{- if .cVersion }}      
- name: CONTAINER_IMAGE_VERSION
  value: {{ .cVersion }}
{{- end }}
- name: K8S_DEPLOYMENT_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
{{- end }}

{{/*
Common volumes for SPK
*/}}
{{- define "volumes.spk" -}}
{{/*
- name: f5log
  configMap:
    name: f5log-min-level
*/}}    
{{- end }}

{{/*
Common volumeMounts for SPK
*/}}
{{- define "volumeMounts.spk" -}}
{{/*
- name: f5log
  mountPath: /logs
*/}}
{{- end }}

{{- define "resource.spk" -}}
apiVersion: v1
kind: {{ .kind }}
metadata:
  name: {{ .name }}
  {{- if .namespace }}
  namespace: {{ .namespace }}
  {{- end }}
  {{- if .labels }}
  labels:
  {{- .labels | nindent 4 }}
  {{- end }}
  {{- if .annotations }}
  annotations:
  {{- .annotations | nindent 4 }}
  {{- end }}
{{- if eq .kind "ConfigMap" }}
data:
{{- if .data }}
  {{- .data | nindent 2 }}
{{- end }}
{{- end }}
{{- if .spec }}
spec:
  {{- .spec | nindent 2 }}
{{- end }}
{{- end }}
