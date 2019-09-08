
locals {
  kops_env_config = {
    KOPS_STATE_STORE  = "s3://${aws_s3_bucket.kops_state.id}"
    KOPS_CLUSTER_NAME = local.cluster_name
  }

  kops_cluster_config = templatefile("${path.module}/templates/cluster.yaml", {
    cluster_name          = local.cluster_name
    cluster_dns           = local.cluster_dns
    cluster_cidr          = "100.0.0.0/8"
    namespace             = var.namespace
    stage                 = var.stage
    region                = var.region
    aws_region            = local.aws_region
    kops_bucket_name      = aws_s3_bucket.kops_state.id
    vpc_id                = local.vpc_id
    vpc_cidr              = local.vpc_cidr
    certificate_arn       = local.certificate_arn
    security_groups       = ""
    public_subnet_id_a    = local.public_subnet_id_a
    public_subnet_cidr_a  = local.public_subnet_cidr_a
    public_subnet_id_b    = local.public_subnet_id_b
    public_subnet_cidr_b  = local.public_subnet_cidr_b
    public_subnet_id_c    = local.public_subnet_id_c
    public_subnet_cidr_c  = local.public_subnet_cidr_c
    private_subnet_id_a   = local.private_subnet_id_a
    private_subnet_cidr_a = local.private_subnet_cidr_a
    private_subnet_id_b   = local.private_subnet_id_b
    private_subnet_cidr_b = local.private_subnet_cidr_b
    private_subnet_id_c   = local.private_subnet_id_c
    private_subnet_cidr_c = local.private_subnet_cidr_c
  })

  kops_default_image = "kope.io/k8s-1.12-debian-stretch-amd64-hvm-ebs-2019-06-21"
  yaml_new_doc       = "\n---\n"
  kops_cluster = format(
    "%s%s%s%s%s",
    local.kops_cluster_config,
    local.yaml_new_doc,
    join(local.yaml_new_doc, data.null_data_source.master_instance_groups.*.outputs.rendered),
    local.yaml_new_doc,
    join(local.yaml_new_doc, data.null_data_source.instance_groups.*.outputs.rendered)
  )
}

data "null_data_source" "instance_groups" {
  count = length(var.instance_groups) * var.max_availability_zones

  inputs = {
    rendered = templatefile("${path.module}/templates/instance-group.yaml", {
      cluster_name           = local.cluster_name
      namespace              = var.namespace
      stage                  = var.stage
      region                 = var.region
      autoscaler             = "enabled"
      node_role              = "Node"
      aws_availability_zone  = element(data.aws_availability_zones.available.names, count.index % var.max_availability_zones)
      image                  = lookup(var.instance_groups[floor(count.index / 3)], "image", local.kops_default_image)
      instance_name          = lookup(var.instance_groups[floor(count.index / 3)], "name")
      instance_type          = lookup(var.instance_groups[floor(count.index / 3)], "instance_type")
      instance_max           = lookup(var.instance_groups[floor(count.index / 3)], "count_max", 3)
      instance_min           = lookup(var.instance_groups[floor(count.index / 3)], "count_min", 1)
      storage_type           = lookup(var.instance_groups[floor(count.index / 3)], "storage_type", "gp2")
      storage_iops           = lookup(var.instance_groups[floor(count.index / 3)], "storage_iops", 168)
      storage_in_gb          = lookup(var.instance_groups[floor(count.index / 3)], "storage_in_gb", 56)
      autospotting_enabled   = lookup(var.instance_groups[floor(count.index / 3)], "autospotting", false)
      autospotting_max_price = lookup(var.instance_groups[floor(count.index / 3)], "autospotting_max_price", "0.01")
    })
  }
}

data "null_data_source" "master_instance_groups" {
  count = var.max_availability_zones

  inputs = {
    rendered = templatefile("${path.module}/templates/instance-group.yaml", {
      cluster_name           = local.cluster_name
      namespace              = var.namespace
      stage                  = var.stage
      region                 = var.region
      image                  = local.kops_default_image
      aws_availability_zone  = element(data.aws_availability_zones.available.names, count.index)
      autoscaler             = "off"
      storage_type           = "io1"
      storage_iops           = 400
      storage_in_gb          = 128
      autospotting_enabled   = false
      autospotting_max_price = "0.001"
      node_role              = "Master"
      instance_name          = "master"
      instance_type          = "t2.medium"
      instance_max           = 1
      instance_min           = 1
    })
  }
}

module "ssh_key_pair" {
  source              = "git::https://github.com/cloudposse/terraform-aws-key-pair.git?ref=tags/0.4.0"
  namespace           = var.namespace
  stage               = var.stage
  attributes          = local.attributes
  tags                = local.tags
  ssh_public_key_path = var.ssh_path
  generate_ssh_key    = "true"
  name                = "kops"
}

resource "null_resource" "kops_update_cluster" {
  provisioner "local-exec" {
    environment = local.kops_env_config
    command     = <<EOF
      echo "${local.kops_cluster}" | kops replace --force -f -;
      kops create secret sshpublickey kops -i ${module.ssh_key_pair.public_key_filename};
      kops update cluster --yes
EOF
  }

  triggers = {
    hash = md5(local.kops_cluster)
  }
}

resource "null_resource" "export_kubecfg" {
  depends_on = [null_resource.kops_update_cluster]

  provisioner "local-exec" {
    command     = "kops export kubecfg"
    environment = local.kops_env_config
  }

  # Always trigger export
  triggers = {
    hash = uuid()
  }
}


resource "null_resource" "kops_delete_cluster" {
  provisioner "local-exec" {
    when        = "destroy"
    command     = "kops delete cluster --yes"
    environment = local.kops_env_config
  }
}
