terraform {
  backend "s3" {
    bucket       = "siase-tfstate-thiago-15soat"
    key          = "siase-auth-lambda/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
