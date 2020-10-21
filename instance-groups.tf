locals {
  require_one_worker_node = var.require_one_node && local.worker_node_min_count == 0
  worker_node_min_count = length(flatten([
    for e in var.instance_groups.*.count_min : range(e)
  ]))

  instance_group_by_zone = flatten([
    for idx, ig in var.instance_groups : [for i in range(lookup(ig, "max_availability_zones", var.max_availability_zones)) : {
      zoned_name = format(
        "%s-%s",
        ig.name,
        element(data.aws_availability_zones.available.names, i)
      )
      config     = ig
      group      = ig.name
      subnet_ids = lookup(ig, "subnet_ids", [element(data.aws_availability_zones.available.names, i)])
    }]
  ])
}

output "instance_group_by_zone" {
  value = local.instance_group_by_zone
}

data "null_data_source" "instance_groups" {
  for_each = {
    for k, v in local.instance_group_by_zone : v.zoned_name => v
  }

  inputs = {
    name = each.value.zoned_name

    rendered = templatefile("${path.module}/templates/instance-group.yaml.tpl", {
      cluster_name           = local.cluster_name
      namespace              = var.namespace
      stage                  = var.stage
      region                 = var.region
      node_role              = "Node"
      extra_node_labels      = lookup(each.value.config, "extra_node_labels", {})
      node_taints            = lookup(each.value.config, "node_taints", [])
      public_ip              = lookup(each.value.config, "associate_public_ip", false)
      autoscaler             = true
      image                  = lookup(each.value.config, "image", "")
      instance_name          = lookup(each.value.config, "name")
      instance_type          = lookup(each.value.config, "instance_type")
      instance_max           = lookup(each.value.config, "count_max", 5)
      instance_min           = lookup(each.value.config, "count_min", 1)
      external_lb_name       = lookup(each.value.config, "loadbalancer_name", "")
      external_target_arn    = lookup(each.value.config, "loadbalancer_target_arn", "")
      storage_type           = lookup(each.value.config, "storage_type", "gp2")
      storage_iops           = lookup(each.value.config, "storage_iops", 0)
      storage_in_gb          = lookup(each.value.config, "storage_in_gb", 32)
      security_group         = lookup(each.value.config, "security_group", "")
      subnet_type            = lookup(each.value.config, "subnet", "private")
      subnet_ids             = each.value.subnet_ids
      autospotting_enabled   = lookup(each.value.config, "autospotting_enabled", true)
      autospotting_on_demand = lookup(each.value.config, "autospotting_on_demand", 0)
      autospotting_max_price = lookup(each.value.config, "autospotting_max_price", 0.03)
      autospotting_instances = distinct(lookup(each.value.config, "autospotting_instances", [lookup(each.value.config, "instance_type")]))
      instance_group_name    = each.value.zoned_name
    })

    name  = each.key
    group = each.value.group
  }
}

data "null_data_source" "master_info" {
  count = var.masters_instance_count

  inputs = {
    name      = format("masters-%d-%s", count.index, element(data.aws_availability_zones.available.names, count.index % var.max_availability_zones))
    subnet_id = element(data.aws_availability_zones.available.names, count.index % var.max_availability_zones)
  }
}

# @TODO Evaluate spot for masters
data "null_data_source" "master_instance_groups" {
  count = var.masters_instance_count

  inputs = {
    name = "masters"
    rendered = templatefile("${path.module}/templates/instance-group.yaml.tpl", {
      cluster_name           = local.cluster_name
      namespace              = var.namespace
      stage                  = var.stage
      region                 = var.region
      public_ip              = false
      autoscaler             = false
      image                  = ""
      security_group         = aws_security_group.masters.id
      external_lb_name       = join("", aws_elb.public_api.*.name)
      external_target_arn    = ""
      instance_group_name    = element(data.null_data_source.master_info.*.outputs.name, count.index)
      subnet_ids             = [element(data.null_data_source.master_info.*.outputs.subnet_id, count.index)]
      subnet_type            = "private"
      storage_type           = "gp2"
      storage_iops           = 0
      storage_in_gb          = 48
      node_role              = "Master"
      extra_node_labels      = {}
      node_taints            = []
      instance_name          = "master"
      instance_max           = 1
      instance_min           = 1
      instance_type          = var.master_machine_type
      autospotting_max_price = 0.19
      autospotting_enabled   = var.masters_spot_enabled && count.index >= var.masters_spot_on_demand
      autospotting_on_demand = count.index < var.masters_spot_on_demand ? 1 : 0
      autospotting_instances = distinct(concat([var.master_machine_type], ["m5.large", "m5.xlarge", "a1.large", "a1.xlarge", "i3.large"]))
    })
  }
}

data "null_data_source" "bastion_instance_group" {
  count = var.bastion_default_instance_count < 1 ? 0 : 1
  inputs = {
    name = "bastions"
    rendered = templatefile("${path.module}/templates/instance-group.yaml.tpl", {
      cluster_name           = local.cluster_name
      namespace              = var.namespace
      stage                  = var.stage
      region                 = var.region
      image                  = ""
      external_lb_name       = ""
      autoscaler             = false
      storage_type           = "gp2"
      storage_iops           = 0
      storage_in_gb          = 8
      autospotting_on_demand = 0
      autospotting_enabled   = true
      autospotting_max_price = 0.008
      autospotting_instances = distinct([var.bastion_machine_type, "t2.small", "t2.medium", "t3.small", "t3.medium"])
      subnet_ids             = slice(data.aws_availability_zones.available.names, 0, var.max_availability_zones)
      external_target_arn    = ""
      external_lb_name       = ""
      security_group         = ""
      subnet_type            = "utility"
      instance_group_name    = "bastion"
      node_role              = "Bastion"
      extra_node_labels      = {}
      node_taints            = []
      instance_name          = "bastion"
      instance_type          = var.bastion_machine_type
      instance_max           = 1
      instance_min           = var.bastion_default_instance_count

      # Bastion requires VPN connection to be accessed
      public_ip = false
    })
  }
}
