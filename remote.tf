
data "terraform_remote_state" "vpc" {
  count   = var.vpc_module_state == "" ? 0 : 1
  backend = "s3"

  config = {
    bucket = var.tf_bucket
    key    = var.vpc_module_state
  }
}

data "terraform_remote_state" "acm" {
  count   = local.acm_module_state == "" ? 0 : 1
  backend = "s3"

  config = {
    bucket = var.tf_bucket
    key    = local.acm_module_state
  }
}

locals {
  acm_module_state = var.acm_module_state == "" && var.dns_module_state != "" && var.certificate_arn == "" ? var.dns_module_state : var.acm_module_state

  vpc_id          = var.vpc_id == "" ? try(data.terraform_remote_state.vpc[0].outputs.vpc_id, "") : var.vpc_id
  vpc_cidr        = var.vpc_cidr == "" ? try(data.terraform_remote_state.vpc[0].outputs.vpc_cidr, "") : var.vpc_cidr
  certificate_arn = var.certificate_arn == "" && var.use_certificate == true ? data.terraform_remote_state.acm[0].outputs.certificate_arn : var.certificate_arn
  cluster_dns     = var.cluster_dns
  cluster_zone_id = var.cluster_zone_id

  public_subnet_ids    = length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : try(data.terraform_remote_state.vpc[0].outputs.public_subnet_ids, [])
  private_subnet_ids   = length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : try(data.terraform_remote_state.vpc[0].outputs.private_subnet_ids, [])
  public_subnet_cidrs  = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : try(data.terraform_remote_state.vpc[0].outputs.public_subnet_cidrs, [])
  private_subnet_cidrs = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : try(data.terraform_remote_state.vpc[0].outputs.private_subnet_cidrs, [])
}
