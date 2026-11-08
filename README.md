# Serverless AI API on AWS: Bedrock + Lambda + Terraform

An HTTPS endpoint that takes a prompt and returns a response from Amazon Nova 2 Lite on Amazon Bedrock. Built with API Gateway (HTTP API), AWS Lambda (Python 3.13) and Terraform, with a least-privilege IAM policy scoped to one inference profile.

```
Client → API Gateway (POST /chat) → Lambda → Bedrock Converse API → Nova 2 Lite
```

## Prerequisites

- An AWS account and credentials configured locally (`aws configure` or SSO)
- Terraform 1.5 or newer
- Amazon Bedrock available in your Region (defaults to `us-east-1`)

## Deploy

```bash
terraform init
terraform apply
```

## Test

```bash
curl -s -X POST "$(terraform output -raw chat_endpoint)" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Explain AWS Lambda cold starts in two sentences."}'
```

## Use a different Region or model

Override variables in a `terraform.tfvars` file (it is git-ignored). Lambda and API Gateway deploy to `aws_region`; the function calls Bedrock in `bedrock_region`, which defaults to the same Region. Splitting them helps when an organization only allows compute in some Regions:

```hcl
aws_region           = "eu-north-1"
bedrock_region       = "eu-west-1"
inference_profile_id = "eu.amazon.nova-2-lite-v1:0"
```

Check the model card in the Bedrock docs for the inference profile ID that matches your Region's geography.

## Clean up

```bash
terraform destroy
```

## Files

| File | Purpose |
| --- | --- |
| `src/handler.py` | Lambda function that calls the Bedrock Converse API |
| `versions.tf` | Terraform and provider versions |
| `variables.tf` | Region, model and throttling settings |
| `iam.tf` | Lambda role and least-privilege Bedrock policy |
| `lambda.tf` | Function, packaging and log group |
| `api.tf` | HTTP API, route, stage throttling and invoke permission |
| `outputs.tf` | Endpoint URL and function name |
