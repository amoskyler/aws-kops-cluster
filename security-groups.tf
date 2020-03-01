
module "masters_sg_label" {
  source    = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  context   = module.label.context
  name      = "masters"
  delimiter = "."
}

resource "aws_security_group" "masters" {
  name        = module.masters_sg_label.id
  tags        = module.masters_sg_label.tags
  description = "Controls traffic to the master nodes of cluster ${local.cluster_name}"
  vpc_id      = local.vpc_id

  egress {
    to_port     = 0
    from_port   = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "masters_ingress" {
  count                    = local.create_additional_loadbalancer ? 1 : 0
  source_security_group_id = aws_security_group.public_loadbalancer.*.id
  security_group_id        = aws_security_group.masters.id
  type                     = "ingress"
  to_port                  = 443
  from_port                = 443
  protocol                 = "tcp"
  description              = "Allows access from a public API Load Balancer security group"
}