variable "name" {
  description = "Tags the zone (Project), so it is easy to find and remove with its deployment."
  type        = string
  default     = "worca-poc"
}

variable "domain" {
  description = "The parent domain, hosted elsewhere (e.g. DigitalOcean). It delegates zone_name to Route 53 with NS records."
  type        = string
}

variable "zone_name" {
  description = "The label delegated to Route 53: the hosted zone is <zone_name>.<domain>."
  type        = string
  default     = "aws"
}

variable "region" {
  type    = string
  default = "eu-central-1"
}
