variable "aws_region" {
  description = "Region the stack is deployed to (the inference profile's source Region)."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used for resource names."
  type        = string
  default     = "bedrock-ai-api"
}

variable "bedrock_region" {
  description = "Region Lambda sends Bedrock requests to. Leave null to use aws_region."
  type        = string
  default     = null
}

variable "foundation_model_id" {
  description = "Base Bedrock model ID."
  type        = string
  default     = "amazon.nova-2-lite-v1:0"
}

variable "inference_profile_id" {
  description = "Cross-Region inference profile ID that Lambda calls. Its prefix (us., eu.) must match bedrock_region's geography."
  type        = string
  default     = "us.amazon.nova-2-lite-v1:0"
}

variable "max_tokens" {
  description = "Maximum tokens the model may generate per request."
  type        = number
  default     = 512
}

variable "throttle_rate_limit" {
  description = "Steady-state requests per second allowed by API Gateway."
  type        = number
  default     = 5
}

variable "throttle_burst_limit" {
  description = "Burst requests allowed by API Gateway."
  type        = number
  default     = 10
}
