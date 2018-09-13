provider "aws" {
  region     = "eu-west-1"
  shared_credentials_file = ".aws_credentials"
  profile    = "default"
}

resource "aws_lambda_function" "rss_from_graphcool" {
  function_name = "CCM_RSS"

  # The bucket name as created earlier with "aws s3api create-bucket"
  s3_bucket = "ccmrsslambdabuilds"
  s3_key    = "bundle.zip"

  # "main" is the filename within the zip file (main.js) and "handler"
  # is the name of the property under which the handler function was
  # exported in that file.
  handler = "bundle.handler"
  runtime = "nodejs8.10"

  # graphcool is sometimes slow...
  timeout = 10

  role = "${aws_iam_role.ccm_rss_lambda_exec.arn}"
}

resource "aws_iam_role" "ccm_rss_lambda_exec" {
  name = "CCM_RSS_Lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_api_gateway_rest_api" "ccm_api_gateway" {
  name        = "CCM_API_Gateway"
  description = "CCM API Gateway"
}

resource "aws_api_gateway_resource" "CCM_RSS" {
  rest_api_id = "${aws_api_gateway_rest_api.ccm_api_gateway.id}"
  parent_id   = "${aws_api_gateway_rest_api.ccm_api_gateway.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = "${aws_api_gateway_rest_api.ccm_api_gateway.id}"
  resource_id   = "${aws_api_gateway_resource.CCM_RSS.id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "gateway_to_lambda" {
  rest_api_id = "${aws_api_gateway_rest_api.ccm_api_gateway.id}"
  resource_id = "${aws_api_gateway_method.proxy.resource_id}"
  http_method = "${aws_api_gateway_method.proxy.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.rss_from_graphcool.invoke_arn}"
}

resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = "${aws_api_gateway_rest_api.ccm_api_gateway.id}"
  resource_id   = "${aws_api_gateway_rest_api.ccm_api_gateway.root_resource_id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "gateway_to_lambda_root" {
  rest_api_id = "${aws_api_gateway_rest_api.ccm_api_gateway.id}"
  resource_id = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.rss_from_graphcool.invoke_arn}"
}

resource "aws_api_gateway_deployment" "production" {
  depends_on = [
    "aws_api_gateway_integration.gateway_to_lambda",
    "aws_api_gateway_integration.gateway_to_lambda_root",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.ccm_api_gateway.id}"
  stage_name  = "production"
}

resource "aws_lambda_permission" "lambda_permission" {
  statement_id  = "AllowInvocationFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.rss_from_graphcool.arn}"
  principal     = "apigateway.amazonaws.com"

  # The /*/*/* part allows invocation from any stage, method and resource path
  # within API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.ccm_api_gateway.execution_arn}/*/*/*"
}


output "base_url" {
  value = "${aws_api_gateway_deployment.production.invoke_url}"
}