locals {
  role_name   = coalesce(var.role_name, join("-", [var.name, "role"]))
  policy_name = coalesce(var.policy_name, join("-", [var.name, "policy"]))
}
