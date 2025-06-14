# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#AWS authentication variables
variable "aws_access_key" {
  type = string
  description = "AWS Access Key"
}
variable "aws_secret_key" {
  type = string
  description = "AWS Secret Key"
}
#AWS Region
variable "aws_region" {
  type = string
  description = "AWS Region"
  default = "us-east-1"
}

variable "PATH_TO_PRIVATE_KEY" {
    default = "./keys/id_ed25519"
}

variable "INSTANCE_USERNAME" {
    default = "ubuntu"
}
