output "chat_endpoint" {
  description = "POST your prompt to this URL."
  value       = "${aws_apigatewayv2_stage.default.invoke_url}chat"
}

output "lambda_function_name" {
  description = "Use this to find the function's logs in CloudWatch."
  value       = aws_lambda_function.chat.function_name
}
