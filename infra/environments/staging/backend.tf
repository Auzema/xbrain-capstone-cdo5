terraform {
  backend "s3" {
    bucket       = "xbrain-capstone-cdo5-staging-i-tfstate"
    key          = "staging/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
