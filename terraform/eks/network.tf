locals {
  availability_zones        = slice(sort(data.aws_availability_zones.available.names), 0, 3)
  vpc_private_subnets_ids   = [for item in data.aws_subnet.private_subnet : item.id]
  vpc_private_subnets_cidrs = [for item in data.aws_subnet.private_subnet : item.cidr_block]
  vpc_private_subnets_arns  = [for item in data.aws_subnet.private_subnet : item.arn]
}

data "aws_subnet" "private_subnet" {
  for_each          = toset(local.availability_zones)
  vpc_id            = var.vpc_id
  availability_zone = each.key
  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
    values = [1]
  }
}

data "aws_subnet" "public_subnet" {
  for_each          = toset(local.availability_zones)
  vpc_id            = var.vpc_id
  availability_zone = each.key
  filter {
    name   = "tag:kubernetes.io/role/elb"
    values = [1]
  }
}