variable "name" {
  description = "Prefix of the repositories (<name>/worca, <name>/worca-worker) and their Project tag."
  type        = string
  default     = "worca-poc"
}

variable "region" {
  description = "The deployments' region: nodes pull from ECR in their own region for free."
  type        = string
  default     = "eu-central-1"
}

variable "repositories" {
  type    = list(string)
  default = ["worca", "worca-worker"]
}

variable "keep_tagged_images" {
  description = "Tagged images kept per repository, the newest first."
  type        = number
  default     = 10
}
