provider "aws" {
  region = local.region
}

locals {
  name            = "opslab"
  region          = "us-east-1"
  subnets         = chunklist([for x in cidrsubnets("10.0.0.0/12", 12, 12, 12, 12, 12, 12, 12) : x if x != cidrsubnets("10.0.0.0/12", 12)[0]], 3)
  cluster_version = "1.21"
  tags = {
    Environment = "development"
    Managedby   = "terraform"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.12.0"

  name            = join("-", [local.name, "vpc"])
  cidr            = cidrsubnets("10.0.0.0/12", 4)[0]
  azs             = [for x in ["a", "b", "c"] : "${local.region}${x}"]
  public_subnets  = local.subnets[0]
  private_subnets = local.subnets[1]

  enable_nat_gateway     = var.vpc.is_enable_natgw
  one_nat_gateway_per_az = var.vpc.is_one_natgw_per_az
  single_nat_gateway     = var.vpc.is_single_natgw
  enable_vpn_gateway     = var.vpc.is_enable_vpngw

  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.tags
}

resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.tags
}

resource "aws_security_group" "additional" {
  name_prefix = "${local.name}-additional"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }

  tags = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "18.7.2"

  cluster_name                    = join("-", [local.name, "eks"])
  cluster_version                 = local.cluster_version
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  cluster_addons = {

    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts = "OVERWRITE"
    }
  }

  cluster_encryption_config = [{
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  self_managed_node_group_defaults = {
    vpc_security_group_ids       = [aws_security_group.additional.id]
    iam_role_additional_policies = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  }

  self_managed_node_groups = {
    spot = {
      instance_type = "m5.large"
      min_size      = 3
      max_size      = 5
      desired_size  = 3
      instance_market_options = {
        market_type = "spot"
      }

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle=spot'"

      post_bootstrap_user_data = <<-EOT
      cd /tmp
      sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
      sudo systemctl enable amazon-ssm-agent
      sudo systemctl start amazon-ssm-agent
      EOT
    }
  }

  tags = local.tags
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_id
}

locals {
  kubeconfig = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "terraform"
    clusters = [{
      name = module.eks.cluster_id
      cluster = {
        certificate-authority-data = module.eks.cluster_certificate_authority_data
        server                     = module.eks.cluster_endpoint
      }
    }]
    contexts = [{
      name = "terraform"
      context = {
        cluster = module.eks.cluster_id
        user    = "terraform"
      }
    }]
    users = [{
      name = "terraform"
      user = {
        token = data.aws_eks_cluster_auth.this.token
      }
    }]
  })
}

resource "null_resource" "apply" {
  triggers = {
    kubeconfig = base64encode(local.kubeconfig)
    cmd_patch  = <<-EOT
      sleep 200
      kubectl create configmap aws-auth -n kube-system --kubeconfig <(echo $KUBECONFIG | base64 -d)
      kubectl patch configmap/aws-auth --patch "${module.eks.aws_auth_configmap_yaml}" -n kube-system --kubeconfig <(echo $KUBECONFIG | base64 -d)
    EOT
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
    command = self.triggers.cmd_patch
  }
}

resource "local_file" "kubeconfig" {
  content  = local.kubeconfig
  filename = "${path.module}/kubeconfig"
}
