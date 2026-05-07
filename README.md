# module3-2-1

## Terraform Variables

This module requires two input variables:

- `log_bucket_name`
- `replica_bucket_arn`

For local runs, create `terraform.tfvars` from `terraform.tfvars.example`.

## CI/CD (GitHub Actions)

Do not commit a real `terraform.tfvars` file.
Set these repository secrets so the pipeline can run `terraform plan`:

- `TF_VAR_LOG_BUCKET_NAME`
- `TF_VAR_REPLICA_BUCKET_ARN`

Terraform automatically maps these to:

- `TF_VAR_log_bucket_name`
- `TF_VAR_replica_bucket_arn`
