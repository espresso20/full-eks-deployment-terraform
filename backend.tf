# Local backend for getting started — no remote state setup required.
# To migrate to S3 remote state, comment out the local block and uncomment the S3 block,
# then run: terraform init -migrate-state

# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }

# S3 remote backend (recommended for team use):
terraform {
  backend "s3" {
    bucket       = "terraform-states-useast1"
    key          = "eks-dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    # dynamodb_table = "<your-lock-table>"
    encrypt = true
    profile = "aroffler-dev-admin-access"
  }
}
