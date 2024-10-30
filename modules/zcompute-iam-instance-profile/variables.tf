variable "name" {
  description = "Instance profile name"
  type        = string
}

variable "instance_profile_path" {
  description = "IAM Instance Profile Path"
  type        = string
  default     = "/"
}
variable "role_path" {
  description = "IAM Role Path"
  type        = string
  default     = "/"
}
variable "policy_path" {
  description = "IAM Policy Path"
  type        = string
  default     = "/"
}

variable "use_existing_role" {
  description = "Controls if an IAM role should be created or reused"
  type        = bool
  default     = false
}
variable "role_name" {
  description = ""
  type        = string
  default     = null
}
variable "role_description" {
  description = ""
  type        = string
  default     = null
  nullable    = true
}
variable "role_contents" {
  description = ""
  type        = any
  default     = null
  nullable    = true
}

variable "use_existing_policy" {
  description = "Controls if an IAM Policy should be created or reused"
  type        = bool
  default     = false
}
variable "policy_name" {
  description = ""
  type        = string
  default     = null
}
variable "policy_description" {
  description = ""
  type        = string
  default     = null
  nullable    = true
}
variable "policy_contents" {
  description = ""
  type        = any
}
variable "policy_arn" {
  description = "ARN to an existing policy to use"
  type        = string
  default     = null
  nullable    = true
}

#variable "tags" {
#  description = "A map of tags to add to all resources"
#  type        = map(string)
#  default     = {}
#}
