terraform {
  backend "s3" {
    bucket       = "apps-terraform-vs-use1"
    key          = "AppS/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # S3 native locking — requires Terraform >= 1.10, no DynamoDB needed
  }
}
