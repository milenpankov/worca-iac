variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "name" {
  description = "Name of the cluster and prefix of everything created."
  type        = string
  default     = "worca-poc"
}

variable "environment" {
  description = "Environment name: tags, and the SSM path /worca/<environment>/ the cluster may read."
  type        = string
  default     = "poc"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Keep it within standard support: extended support costs 6x."
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "availability_zones" {
  description = "Two AZs (EKS needs subnets in at least two). The system node group runs in the first, so the controller's EBS volume stays reachable."
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

variable "system_instance_types" {
  description = "The always-on node: Worca controller, oauth2-proxy, Argo CD, Traefik, cert-manager, External Secrets, Cluster Autoscaler. 8 GB is the comfortable minimum."
  type        = list(string)
  default     = ["t3a.large"]
}

variable "worker_instance_types" {
  description = "Spot instance types for worker pods (several types: better spot availability)."
  type        = list(string)
  default     = ["t3a.large", "t3.large", "m5a.large", "m6a.large"]
}

variable "worker_max_nodes" {
  description = "Most worker nodes the autoscaler may start. 0 nodes while no run is active."
  type        = number
  default     = 2
}

variable "cluster_admin_arns" {
  description = "IAM principals (users or roles) given cluster-admin, besides the identity that runs terraform apply."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
