
locals {
  kops_env_config = {
    KOPS_CLUSTER_NAME     = local.cluster_name
    KOPS_STATE_STORE      = "s3://${aws_s3_bucket.kops_state.id}"
    AWS_ACCESS_KEY_ID     = var.external_account ? join("", aws_iam_access_key.kops.*.id) : ""
    AWS_SECRET_ACCESS_KEY = var.external_account ? join("", aws_iam_access_key.kops.*.secret) : ""
    AWS_DEFAULT_REGION    = local.aws_region
  }

  kops_cluster_config = templatefile("${path.module}/templates/cluster.yaml.tpl", {
    cluster_name           = local.cluster_name
    cluster_zone_id        = local.cluster_zone_id
    dns_type               = var.cluster_dns_type
    k8s_version            = var.kubernetes_version
    etcd_version           = var.etcd_version
    cluster_cidr           = "100.64.0.0/10"
    namespace              = var.namespace
    stage                  = var.stage
    region                 = var.region
    addons                 = var.kops_addons
    aws_region             = local.aws_region
    aws_zones              = slice(data.aws_availability_zones.available.names, 0, var.max_availability_zones)
    kops_bucket_name       = aws_s3_bucket.kops_state.id
    vpc_id                 = local.vpc_id
    vpc_cidr               = local.vpc_cidr
    ssh_access             = length(var.ssh_access_cidrs) > 0 ? var.ssh_access_cidrs : [local.vpc_cidr]
    api_access             = distinct(concat(var.create_public_api_record ? ["0.0.0.0/0"] : [], length(var.api_access_cidrs) > 0 ? var.api_access_cidrs : [var.cluster_dns_type != "Private" ? "0.0.0.0/0" : local.vpc_cidr]))
    certificate_arn        = local.certificate_arn
    lb_type                = var.cluster_dns_type == "Private" ? "Internal" : "Public"
    cluster_api_type       = var.cluster_api_type
    enable_psp             = var.enable_pod_security_policies
    bastion_public_name    = var.bastion_public_name
    public_subnet_ids      = local.public_subnet_ids
    private_subnet_ids     = local.private_subnet_ids
    public_subnet_cidrs    = local.public_subnet_cidrs
    private_subnet_cidrs   = local.private_subnet_cidrs
    disable_subnet_tags    = var.disable_subnet_tags
    etcd_members           = data.null_data_source.master_info.*.outputs.name
    etcd_main_volume_type  = var.etcd_main_storage_type
    etcd_main_volume_iops  = var.etcd_main_storage_iops
    etcd_main_volume_size  = var.etcd_main_storage_size
    etcd_event_volume_type = var.etcd_events_storage_type
    etcd_event_volume_iops = var.etcd_events_storage_iops
    etcd_event_volume_size = var.etcd_events_storage_size

    max_requests_in_flight          = var.max_requests_in_flight
    max_mutating_requests_in_flight = var.max_mutating_requests_in_flight

    has_external_policies      = length(var.external_master_policies) > 0
    external_master_policies   = var.external_master_policies
    additional_master_policies = var.additional_master_policies == "" ? "" : indent(6, var.additional_master_policies)

    openid_connect_enabled = var.openid_connect_enabled
    oidc_issuer_url        = var.oidc_issuer_url
    oidc_client_id         = var.oidc_client_id
    oidc_username_claim    = var.oidc_username_claim
    oidc_username_prefix   = var.oidc_username_prefix
    oidc_groups_claim      = var.oidc_groups_claim
    oidc_groups_prefix     = var.oidc_groups_prefix
    oidc_ca_file           = var.oidc_ca_file
    oidc_ca_content        = var.oidc_ca_content
    oidc_required_claims   = var.oidc_required_claims
  })

  kops_configs = concat(
    [local.kops_cluster_config],
    data.null_data_source.bastion_instance_group.*.outputs.rendered,
    data.null_data_source.master_instance_groups.*.outputs.rendered,
  )

  kops_cluster_triggers = {
    cluster             = join("\n---\n\n", local.kops_configs)
    instance_group_hash = md5(yamlencode(local.kops_instance_groups))
    cluster_hash        = md5(yamlencode(local.kops_configs))
  }

  kops_instance_groups = {
    for k, v in data.null_data_source.instance_groups : k => {
      content_hash = md5(v.outputs.rendered)
      content      = v.outputs.rendered
    }
  }

  kops_yaml_config_dir = "${var.cluster_config_path}/${local.cluster_name}/yaml"

  public_key = var.public_key_path == null ? try(module.ssh_key_pair[0].public_key_filename, "") : var.public_key_path
}

module "ssh_key_pair" {
  count               = var.public_key_path == null ? 1 : 0
  source              = "git::https://github.com/cloudposse/terraform-aws-key-pair.git?ref=tags/0.14.0"
  namespace           = var.namespace
  stage               = var.stage
  attributes          = local.attributes
  tags                = local.tags
  ssh_public_key_path = format("%s/ssh", var.secrets_path)
  generate_ssh_key    = "true"
  name                = "kops"
}

resource "local_file" "cluster_config" {
  content  = local.kops_cluster_triggers.cluster
  filename = "${local.kops_yaml_config_dir}/cluster.yaml"
}

resource "local_file" "instance_group_config" {
  # for_each = local.kops_instance_groups
  for_each = data.null_data_source.instance_groups

  content  = each.value.outputs.rendered
  filename = "${local.kops_yaml_config_dir}/${each.key}.yaml"
}

# Replaces the cluster or creates it if it does not yet exist
resource "null_resource" "replace_cluster" {
  depends_on = [
    aws_s3_bucket_public_access_block.block,
    local_file.cluster_config
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = local.kops_env_config
    command     = "kops replace --force -f ${local.kops_yaml_config_dir}/cluster.yaml"
  }

  triggers = local.kops_cluster_triggers
}

resource "null_resource" "replace_instance_groups" {
  for_each = local.kops_instance_groups

  depends_on = [
    aws_s3_bucket_public_access_block.block,
    local_file.instance_group_config
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = local.kops_env_config
    command     = "kops replace --force -f ${local.kops_yaml_config_dir}/${self.triggers.instance_group_name}.yaml"
  }

  triggers = {
    instance_group_name = each.key
    instance_group_hash = each.value.content_hash
  }
}

resource "null_resource" "kops_delete_instance_groups" {
  for_each = local.kops_instance_groups

  triggers = local.kops_env_config

  provisioner "local-exec" {
    when        = destroy
    command     = "kops delete instancegroup ${each.key} --yes"
    environment = self.triggers
  }
}


resource "null_resource" "set_sshpublickey" {
  depends_on = [
    null_resource.replace_cluster,
  ]

  provisioner "local-exec" {
    environment = local.kops_env_config
    interpreter = ["bash", "-c"]
    command     = "kops create secret sshpublickey admin -i ${self.triggers.key_path}"
  }

  triggers = {
    key_path = local.public_key
  }
}

resource "null_resource" "update_cluster_tf" {
  depends_on = [
    null_resource.replace_cluster,
    null_resource.replace_instance_groups,
    null_resource.set_sshpublickey
  ]

  provisioner "local-exec" {
    environment = local.kops_env_config
    interpreter = ["bash", "-c"]
    command     = "kops update cluster --target terraform --out ${var.cluster_config_path}/${local.cluster_name}"
  }

  triggers = local.kops_cluster_triggers
}

# resource "null_resource" "kops_delete_cluster" {
#   triggers = local.kops_env_config
#   provisioner "local-exec" {
#     when        = destroy
#     command     = "kops delete cluster --yes"
#     environment = self.triggers
#   }
# }
