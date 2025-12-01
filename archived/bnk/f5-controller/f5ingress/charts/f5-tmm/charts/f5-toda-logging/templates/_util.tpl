{{- /*
f5-toda-logging.util.merge will merge two YAML templates and output the result.
This takes an array of three values:
- the top context
- the template name of the overrides (destination)
- the template name of the base (source)
Additionally:
- add TODA "volumes" to original "volumes"
- add TODA "env" variables and "volumeMounts" to original containers

"default" used to avoid cases when section is not present in original scheme
*/ -}}
{{- define "f5-toda-logging.util.merge" -}}
{{- $top := first . -}}
{{- $overrides := fromYaml (include (index . 1) $top) | default (dict ) -}}
{{- $tpl := fromYaml (include (index . 2) $top) | default (dict ) -}}

{{- /* if yaml is empty, return empty string */ -}}
{{- if hasKey $overrides "metadata" -}}

    {{- /* get tmm container name from annotations */ -}}
    {{- $tmm_name := "" -}}
    {{- if hasKey $overrides.metadata "annotations" -}}
        {{- $tmm_name = get $overrides.metadata.annotations "toda.f5.com/tmm-name" -}}
    {{- end -}}

    {{- /* if type is stdout and no tmm container - skip update on yaml */ -}}
    {{- if or (eq (index $top.Values "f5-toda-logging" "type") "generic") $tmm_name -}}
        {{- /* "merge" func merge only keys so it overwrite list values. Make sure that "volumes" values are merged */ -}}
        {{- $_ := set $overrides.spec.template.spec "volumes" (concat ($overrides.spec.template.spec.volumes | default list) (index $top.Values "f5-toda-logging" "volumeTmstat")) -}}
        {{- if index $top.Values "f5-toda-logging" "tmstats" "f5_csm_qkview" "enabled" -}}
            {{- if index $top.Values "f5-toda-logging" "tmstats" "cert_manager" "enabled" -}}
                {{- $_ := set $overrides.spec.template.spec "volumes" (concat ($overrides.spec.template.spec.volumes | default list) (index $top.Values "f5-toda-logging" "certOrchestratorQkviewVolume")) -}}
            {{- else -}}
                {{- $_ := set $overrides.spec.template.spec "volumes" (concat ($overrides.spec.template.spec.volumes | default list) (index $top.Values "f5-toda-logging" "withoutCertOrchestratorWithoutQkviewVolume")) -}}
            {{- end -}}
        {{- end -}}

        {{- /* add tmstats if enabled and tmm containers */ -}}
        {{- if and (index $top.Values "f5-toda-logging" "tmstats" "enabled") $tmm_name -}}
            {{- template "f5-toda-logging.util.addTmstats" (list (index $top.Values "f5-toda-logging") $overrides.spec.template.spec)  -}}
        {{- end -}}
    {{- end -}}
    {{- $result := merge $overrides $tpl -}}
    {{- toYaml $result -}}
    {{- end -}}
{{- end -}}

{{- /*
f5-toda-logging.util.addTmstats add tmstats demon to existing containers
*/ -}}
{{- define "f5-toda-logging.util.addTmstats" -}}
{{- $logValues := first . -}}
{{- $spec := last . -}}
{{- $tmstats :=  $logValues.tmstats.config | deepCopy -}}
{{- $imagerepository := $tmstats.image.repository | required "tmstats.image.repository is required." -}}
{{- $imagename := $tmstats.image.name -}}
{{- $imagetag := $tmstats.image.tag -}}
{{- $newimage := printf "%s/%s:%s" $imagerepository $imagename $imagetag -}}
{{- $newtmstats := omit $tmstats "image" -}}
{{- $_ := set $newtmstats "image" $newimage -}}
{{- $_ := set $newtmstats "ports" $tmstats.ports -}}
{{- $_ := set $newtmstats "volumeMounts" (concat $newtmstats.volumeMounts $logValues.certOrchestratorVolumeMount) -}}
{{- if $logValues.tmstats.f5_csm_qkview.enabled -}}
    {{- $_ := set $newtmstats "env" (concat $newtmstats.env $logValues.qkviewMount.env) -}}
    {{- if $logValues.tmstats.cert_manager.enabled -}}
        {{- $_ := set $newtmstats "volumeMounts" (concat $newtmstats.volumeMounts $logValues.certOrchestratorQkviewVolumeMount) -}}
    {{- else -}}
        {{- $_ := set $newtmstats "volumeMounts" (concat $newtmstats.volumeMounts $logValues.withoutCertOrchestratorQkviewVolumeMount) -}}
    {{- end -}}
{{- end -}}
{{- if or (eq $logValues.global.platformType "robin") (eq $logValues.global.platformType "other") -}}
    {{- $_ := set $newtmstats "volumeMounts" (concat $newtmstats.volumeMounts $logValues.volumeMountCoreTmstat) -}}
{{- end -}}
{{- $_ := set $spec "containers" (append $spec.containers $newtmstats) -}}
{{- end -}}

{{/*
Create service name
*/}}
{{- define "f5-toda-logging.svcName" -}}
{{- printf "%s.%s" "f5-toda-logging" .Release.Namespace | trunc 63 | trimSuffix "-" }}
{{- end }}
