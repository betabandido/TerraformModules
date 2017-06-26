provider "aws" {
  profile = "${var.profile}"
  region  = "${var.region}"
}

### API ###

resource "aws_api_gateway_rest_api" "api" {
 name = "${var.prefix}ApiMethod"
}

### Test for query strings ###

module "method" {
  source = "../../modules/api_method"
  api    = "${aws_api_gateway_rest_api.api.id}"
  parent = "${aws_api_gateway_rest_api.api.root_resource_id}"
  querystrings = {
    q = true
  }
  request = {
    type = "MOCK"
    content_type = "application/json"
    template = <<EOF
{"statusCode": #if($input.params('q')=="existing")200#{else}404#end}
EOF
  }
  responses = {
    "200" = {
      content_type = "text/plain"
      selection_pattern = ""
      template = "Found"
    }
    "404" = {
      content_type = "text/plain"
      selection_pattern = "404"
      template = "Not found"
    }
  }
}

### Test for headers ###

module "path" {
  source = "../../modules/api_path/path1"
  api    = "${aws_api_gateway_rest_api.api.id}"
  parent = "${aws_api_gateway_rest_api.api.root_resource_id}"
  path   = ["redirect"]
}

module "redirect_method" {
  source = "../../modules/api_method"
  api    = "${aws_api_gateway_rest_api.api.id}"
  parent = "${element(module.path.path_resource_id, 0)}"
  request = {
    type = "MOCK"
    content_type = "application/json"
    template = <<EOF
{"statusCode": 301}
EOF
  }
  headers = { Location = "http://www.example.com" }
  responses = {
    "301" = {
      selection_pattern = ""
    }
  }
}


### Test for cache key parameters ###

module "param" {
  source = "../../modules/api_path/path2"
  api    = "${aws_api_gateway_rest_api.api.id}"
  parent = "${aws_api_gateway_rest_api.api.root_resource_id}"
  path   = ["caching", "{param}"]
}

module "caching_method" {
  source = "../../modules/api_method"
  api    = "${aws_api_gateway_rest_api.api.id}"
  parent = "${element(module.param.path_resource_id, 1)}"
  request = {
    type = "MOCK"
    content_type = "application/json"
    template = <<EOF
{"statusCode": 200}
EOF
  }
  cache_key_parameters = ["param"]
  responses = {
    "200" = {
      content_type = "text/plain"
      selection_pattern = ""
      template = "OK"
    }
  }
}

### Deployment ###

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = ["module.method", "module.redirect_method"]
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  stage_name  = "Test"

  provisioner "local-exec" {
    command = "ruby ../../build/wait_for_url.rb ${aws_api_gateway_deployment.deployment.invoke_url}"
  }

  provisioner "local-exec" {
    command = "ruby ../../build/wait_for_url.rb ${aws_api_gateway_deployment.deployment.invoke_url}/redirect"
  }
}

output "api_url" {
  value = "${aws_api_gateway_deployment.deployment.invoke_url}"
}
