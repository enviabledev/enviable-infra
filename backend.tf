terraform {
  backend "s3" {
    # bucket is supplied at init time (partial config) so the account-id-bearing
    # name stays out of this public repo:
    #   terraform init -backend-config="bucket=enviable-tfstate-<account_id>"
    key            = "prod/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "enviable-tf-lock"
    encrypt        = true
  }
}
