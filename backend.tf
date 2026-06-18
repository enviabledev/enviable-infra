terraform {
  backend "s3" {
    bucket         = "enviable-tfstate-REPLACE_WITH_ACCOUNT_ID"
    key            = "prod/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "enviable-tf-lock"
    encrypt        = true
  }
}
