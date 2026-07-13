# EKS com recursos NATIVOS (não o módulo terraform-aws-modules/eks).
# Motivo: o módulo sempre avalia data.aws_iam_session_context → iam:GetRole na role
# `voclabs`, que o Learner Lab NEGA. Recursos nativos evitam essa chamada.
# Learner Lab: cluster e node group reusam o LabRole (sem criar roles).

locals {
  # Role da sessão do lab — recebe admin no cluster via access entry (sem GetRole).
  admin_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/voclabs"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = var.lab_role_arn # LabRole como cluster role

  vpc_config {
    subnet_ids              = concat(module.vpc.private_subnets, module.vpc.public_subnets)
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  # Sem encryption_config (KMS) e sem enabled_cluster_log_types → evita chamadas que o lab nega.
  tags = {
    Project = "FiapCloudGames"
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = var.lab_role_arn # LabRole como node role
  subnet_ids      = module.vpc.private_subnets
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired
    min_size     = var.node_min
    max_size     = var.node_max
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Project = "FiapCloudGames"
  }

  depends_on = [aws_eks_cluster.this]
}

# Admin do cluster para a role da sessão do lab (assim o kubectl do usuário funciona).
resource "aws_eks_access_entry" "voclabs" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = local.admin_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "voclabs_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = local.admin_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.voclabs]
}

# Namespaces (fcg-dev/fcg-prd) e ESO são criados PÓS-apply via kubectl/helm (gateway é o
# AWS API Gateway, criado pelo próprio apply — ver apigateway.tf; não mais Kong)
# (ver README.md) — evita o problema de bootstrap do provider kubernetes no mesmo root.
