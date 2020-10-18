apiVersion: kops.k8s.io/v1alpha2
kind: Cluster
metadata:
  name: ${cluster_name}
  labels:
    kops.k8s.io/cluster: ${cluster_name}
spec:
  cloudProvider: aws
  kubernetesVersion: ${k8s_version}
  masterPublicName: ${cluster_name}
  masterInternalName: internal.${cluster_name}
  networkID: ${vpc_id}
  networkCIDR: ${vpc_cidr}
  awsRegion: ${aws_region}
  dnsZone: ${cluster_zone_id}
  nonMasqueradeCIDR: ${cluster_cidr}
  configBase: s3://${kops_bucket_name}/${cluster_name}
  disableSubnetTags: ${disable_subnet_tags}
  authorization:
    rbac: {}
  iam:
    legacy: false
%{ if length(api_access) > 0 ~}
  kubernetesApiAccess:
%{ for cidr in api_access ~}
  - ${cidr}
%{ endfor ~}
%{ endif ~}
%{ if length(ssh_access) > 0 ~}
  sshAccess:
%{ for cidr in ssh_access ~}
  - ${cidr}
%{ endfor ~}
%{ endif ~}
%{ if length(addons) > 0 ~}
  addons:
%{ for addon in addons ~}
  - manifest: ${addon}
%{ endfor ~}
%{ endif ~}
  networking:
    calico:
      majorVersion: v3
%{ if additional_master_policies != "" ~}
  additionalPolicies:
    master: |
      ${additional_master_policies}
%{ endif ~}
%{ if has_external_policies ~}
  externalPolicies:
    master:
%{ for policy in external_master_policies ~}
    - ${policy}
%{ endfor ~}
%{ endif ~}
  api:
%{ if cluster_api_type == "dns" ~}
    dns: {}
%{ else ~}
    loadBalancer:
      type: ${lb_type}
%{ endif ~}
%{ if certificate_arn != "" ~}
      sslCertificate: "${certificate_arn}"
%{ endif ~}
  kubeControllerManager:
    featureGates:
      TTLAfterFinished: "true"
  kubeAPIServer:
    featureGates:
      TTLAfterFinished: "true"
    admissionControl:
%{ if enable_psp ~}
    - PodSecurityPolicy
%{ endif ~}
    - NamespaceLifecycle
    - LimitRanger
    - ServiceAccount
    - DefaultStorageClass
    - DefaultTolerationSeconds
    - MutatingAdmissionWebhook
    - ValidatingAdmissionWebhook
    - ResourceQuota
    maxRequestsInflight: ${max_requests_in_flight}
    maxMutatingRequestsInflight: ${max_mutating_requests_in_flight}
%{ if openid_connect_enabled ~}
    oidcIssuerURL: ${oidc_issuer_url}
    oidcClientID: ${oidc_client_id}
    oidcUsernameClaim: ${oidc_username_claim}
    oidcUsernamePrefix: "${oidc_username_prefix}"
    oidcGroupsClaim: ${oidc_groups_claim}
    oidcGroupsPrefix: "${oidc_groups_prefix}"
%{ if oidc_ca_file != "" || oidc_ca_content != "" ~}
    oidcCAFile: /etc/ssl/certs/oidc-issuer-ca
%{ endif ~}
%{ if length(oidc_required_claims) > 0 ~}
    oidcRequiredClaim:
%{ for claim in oidc_required_claims ~}
    - "${claim.key}=${claim.value}"
%{ endfor ~}
%{ endif ~}
%{ endif ~}
  kubelet:
    anonymousAuth: false
    authenticationTokenWebhook: true
    featureGates:
      HPAScaleToZero: "true"
  docker:
    logDriver: json-file
    logOpt:
    - max-size=32m
    - max-file=20
  kubeProxy:
    cpuRequest: 50m
    cpuLimit: 150m
    memoryRequest: 84Mi
  channel: stable
  cloudLabels:
    Namespace: ${namespace}
    Stage: ${stage}
    Region: ${region}
    kops.k8s.io/cluster: ${cluster_name}
%{ if oidc_ca_file != "" || oidc_ca_content != "" ~}
  fileAssets:
  - name: oidc-issuer-ca
    path: /etc/ssl/certs/oidc-issuer-ca
    roles: [Master]
    content: |
      ${indent(6, oidc_ca_content == "" ? file(oidc_ca_file) : oidc_ca_content)}
%{ endif ~}
  etcdClusters:
  - cpuRequest: 200m
    etcdMembers:
%{ for index, member in etcd_members ~}
    - encryptedVolume: true
      instanceGroup: ${member}
      name: master-${index}
%{ if etcd_main_volume_iops != 0 ~}
      volumeIops: ${etcd_main_volume_iops}
%{ endif ~}
%{ endfor ~}
    name: main
    enableEtcdTLS: true
    memoryRequest: 156Mi
  - cpuRequest: 120m
    etcdMembers:
%{ for index, member in etcd_members ~}
    - encryptedVolume: true
      instanceGroup: ${member}
      name: master-${index}
%{ if etcd_main_volume_iops != 0 ~}
      volumeIops: ${etcd_event_volume_iops}
%{ endif ~}
%{ endfor ~}
    name: events
    memoryRequest: 156Mi
    enableEtcdTLS: true
  subnets:
%{ for index, id in public_subnet_ids ~}
  - id: ${id}
    cidr: ${element(public_subnet_cidrs, index)}
    name: utility-${element(aws_zones, index)}
    type: Utility
    zone: ${element(aws_zones, index)}
%{ endfor ~}
%{ for index, id in private_subnet_ids ~}
  - id: ${id}
    cidr: ${element(private_subnet_cidrs, index)}
    name: private-${element(aws_zones, index)}
    type: Private
    zone: ${element(aws_zones, index)}
%{ endfor ~}
  topology:
    dns:
      type: ${dns_type}
    masters: private
    nodes: public
#     bastion:
#       idleTimeoutSeconds: 900
# %{ if bastion_public_name != "" ~}
#       bastionPublicName: ${bastion_public_name}.${cluster_name}
# %{ endif ~}
