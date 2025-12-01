{{- /* f5-tmm container resources template */ -}}
{{- define "tmm.resources" -}}
limits:
  cpu: {{ .limits_cpu }}
  {{- if .hpg_enabled }}
  hugepages-2Mi: {{ .limits_hpg | quote }}
  {{- end }}
  memory: {{ .mem_mb_overhead | quote }}
  {{- if .sriov_resources }}
  {{- range $key, $value := .sriov_resources }}
  {{ $key }}: {{ $value }}
  {{- end }}
  {{- end }}
requests:
  cpu: {{ .limits_cpu }}
  {{- if .hpg_enabled }}
  hugepages-2Mi: {{ .limits_hpg | quote }}
  {{- end }}
  memory: {{ .mem_mb_overhead | quote }}
  {{- if .sriov_resources }}
  {{- range $key, $value := .sriov_resources }}
  {{ $key }}: {{ $value }}
  {{- end }}
  {{- end }}
{{- end }}
