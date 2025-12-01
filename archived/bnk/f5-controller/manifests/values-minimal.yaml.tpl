# values-minimal.yaml.tpl
# Minimal working F5 SPK deployment

global:
  imageCredentials:
    name: ${far_secret_name}

imageCredentials:
  name: ${far_secret_name}

controller:
  image:
    repository: ${image_registry}/images
  
  watchNamespace: ${namespace}
  
  createTmmLBService: false
  
  tmm_pod_manager:
    image:
      repository: ${image_registry}/images
  
  f5_lic_helper:
    enabled: true
    name: f5-lic-helper
    image:
      repository: ${image_registry}/images
    rabbitmqNamespace: ${rabbitmq_namespace}
    rabbitmqCerts:
      ca_root_cert: null
      client_cert: null
      client_key: null
  
  fluentbit_sidecar:
    enabled: false
    fluentd:
      host: localhost
  
  otel_sidecar:
    enabled: false
    prometheus_nodePort: 30000
  
  grafana:
    enabled: false
    port: 32000
  
  prometheus:
    enabled: false
    port: 30000

f5-tmm:
  enabled: true
  
  cert-orchestrator:
    enabled: true
  
  debug:
    image:
      repository: ${image_registry}/images
    rabbitmqNamespace: ${rabbitmq_namespace}
  
  blobd:
    enabled: false
    image:
      repository: ${image_registry}/images
  
  f5-toda-logging:
    enabled: false
    fluentbit:
      tls:
        enabled: false
    fluentd:
      host: f5-toda-fluentd.${rabbitmq_namespace}.svc.cluster.local.
      port: 54321
    tmstats:
      enabled: false
      config:
        image:
          repository: ${image_registry}/images
  
  tmm:
    image:
      repository: ${image_registry}/images
    
    nodeSelector:
      node-type: high-performance
    
    tolerations:
      - key: f5.com/spk-node
        operator: Equal
        value: "true"
        effect: NoSchedule
      - key: high-performance
        operator: Equal
        value: "true"
        effect: NoSchedule
    
    cniNetworks: ${namespace}/${external_nad_name}, ${namespace}/${internal_nad_name}
    
    customEnvVars:
      - name: ROBIN_VFIO_RESOURCE_1
        value: "external_netdevice"
      - name: ROBIN_VFIO_RESOURCE_2
        value: "internal_netdevice"
      - name: PCIDEVICE_INTEL_COM_EXTERNAL_NETDEVICE
        value: "0000:00:07.0"
      - name: PCIDEVICE_INTEL_COM_INTERNAL_NETDEVICE
        value: "0000:00:06.0"
      - name: TMM_IGNORE_GATEWAYS
        value: "TRUE"
      - name: PAL_CPU_SET
        value: "0"
      - name: TMM_MAPRES_IGNORE_MEM_LIMIT
        value: "TRUE"
      - name: SESSIONDB_EXTERNAL_SERVICE
        value: "${dssm_sentinel_host}:${dssm_sentinel_port}"
    
    debug:
      enabled: true
    
    dynamicRouting:
      enabled: false
    
    grpc:
      enabled: true
    
    icni2:
      enabled: false
    
    hugepages:
      enabled: true
    
    tlsStore:
      enabled: false
    
    resources:
      limits:
        cpu: ${cpu_cores}
        memory: ${memory}
        hugepages-2Mi: ${hugepages_2mi}