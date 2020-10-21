terraform {
  required_version = ">= 0.13"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # version = "~> 3.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  attributes     = concat(var.attributes, [var.region])
  tags           = merge(var.tags, map("KubernetesCluster", local.cluster_name))
  cluster_name   = var.cluster_name == "" ? format("%s.%s.%s", var.stage, var.region, var.namespace) : var.cluster_name
  aws_region     = var.aws_region == "" ? data.aws_region.current.name : var.aws_region
  aws_account_id = var.aws_account_id == "" ? data.aws_caller_identity.current.account_id : var.aws_account_id
}

module "label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.19.2"
  name       = var.name
  namespace  = var.namespace
  stage      = var.stage
  delimiter  = var.delimiter
  attributes = local.attributes
  tags       = local.tags
}

module "kops_label" {
  source  = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.19.2"
  context = module.label.context
  # name    = "kops"
}
