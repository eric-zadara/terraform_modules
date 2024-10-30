variable "vpc_id" {
  description = "zCompute VPC ID"
  type        = string
}

variable "subnets" {
  description = "A list of (preferably private) subnets to place the K8s cluster and workers into."
  type        = list(string)
}

variable "cluster_name" {
  description = "Name to be used to describe the k8s cluster"
  type        = string
}

variable "cluster_version" {
  description = "The k8s base version to use"
  type        = string
}

variable "cluster_token" {
  description = "Configure the node join token"
  type        = string
  default     = null
}

variable "cluster_flavor" {
  description = "Default flavor of k8s cluster to deploy"
  type        = string
  default     = "k3s-ubuntu"
}

variable "cluster_helm" {
  description = "List of helmcharts to preload"
  type        = any
  default     = {}
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "node_group_defaults" {
  description = "User-configurable defaults for all node groups"
  type    = any
  default = {}
}

variable "node_groups" {
  description = "Configuration of scalable hosts with a designed configuration."
  type    = any
  default = {}
}
