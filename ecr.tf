resource "aws_ecr_repository" "hello_server" {
  name                 = "hello-server"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # allows destroy even when images are present

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "hello_server" {
  repository = aws_ecr_repository.hello_server.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

output "ecr_repository_url" {
  description = "ECR repository URL — use this as the image prefix when pushing"
  value       = aws_ecr_repository.hello_server.repository_url
}
