# ECR é infra compartilhada (spec 01) — criada pela plataforma.
# (Os repos não existiam nesta conta do lab; criamos aqui.)
resource "aws_ecr_repository" "repos" {
  for_each             = toset(var.ecr_repos)
  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = "FiapCloudGames"
  }
}
