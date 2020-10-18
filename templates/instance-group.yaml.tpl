apiVersion: kops.k8s.io/v1alpha2
kind: InstanceGroup
metadata:
  name: ${instance_group_name}
  labels:
    kops.k8s.io/cluster: ${cluster_name}
    kops.k8s.io/instancegroup: ${instance_group_name}
spec:
  cloudLabels:
    Namespace: ${namespace}
    Stage: ${stage}
    Region: ${region}
    InstanceType: ${instance_name}
    InstanceGroup: ${instance_group_name}
    kops.k8s.io/cluster: ${cluster_name}
    kubernetes.io/cluster/${cluster_name}: owned
%{ if autoscaler ~}
    k8s.io/cluster-autoscaler/enabled: ""
    k8s.io/cluster-autoscaler/node-template/label/InstanceType: ${instance_name}
    k8s.io/cluster-autoscaler/node-template/label/InstanceGroup: ${instance_group_name}
%{ endif ~}
%{ if image != "" ~}
  image: ${image}
%{ endif ~}
  machineType: ${instance_type}
  maxSize: ${instance_max}
  minSize: ${instance_min}
  rootVolumeSize: ${storage_in_gb}
  rootVolumeType: ${storage_type}
  rootVolumeIops: ${storage_iops}
  associatePublicIp: ${public_ip}
%{ if security_group != "" ~}
  securityGroupOverride: ${security_group}
%{ endif ~}
%{ if external_lb_name != "" || external_target_arn != "" ~}
  externalLoadBalancers:
  %{ if external_lb_name != "" }
  - loadBalancerName: ${external_lb_name}
  %{ endif }
  %{ if external_target_arn != "" }
  - targetGroupArn: ${external_target_arn}
  %{ endif }
%{ endif ~}
%{ if autospotting_enabled ~}
  maxPrice: "${autospotting_max_price}"
  mixedInstancesPolicy:
    onDemandAboveBase: ${autospotting_on_demand}
    # https://github.com/kubernetes/kops/issues/7405
    # spotAllocationStrategy: diversified
    instances:
  %{ for instance in autospotting_instances ~}
    - ${instance}
  %{ endfor ~}
%{ endif }
  nodeLabels:
    Namespace: ${namespace}
    Stage: ${stage}
    Region: ${region}
    InstanceType: ${instance_name}
    InstanceGroup: ${instance_group_name}
    kops.k8s.io/cluster: ${cluster_name}
    kops.k8s.io/instancegroup: ${instance_group_name}
%{ if autospotting_enabled ~}
    spot: "true"
%{ endif ~}
  role: ${node_role}
  subnets: 
  %{ for subnet in subnet_ids ~}
  - ${subnet_type}-${subnet}
  %{ endfor }  
