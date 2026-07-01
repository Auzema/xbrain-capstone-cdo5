terraform {
  backend "s3" {
    bucket       = "xbrain-capstone-cdo5-sandbox-i-tfstate"
    key          = "sandbox/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
