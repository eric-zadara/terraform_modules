locals {
  policy_name_hash = join("-", [local.policy_name, md5(jsonencode(var.policy_contents))])
}
data "aws_iam_policy_document" "policy" {
  version = "2012-10-17"
}
resource "aws_iam_policy" "this" {
  count       = var.use_existing_policy ? 0 : 1
  name        = local.policy_name_hash
  path        = var.policy_path
  description = try(var.policy_description, "Policy for iam role ${var.role_name}")
  policy      = var.policy_contents != null ? jsonencode(var.policy_contents) : data.aws_iam_policy_document.policy.json
}

resource "aws_iam_policy_attachment" "this" {
  count      = var.use_existing_policy ? 0 : 1
  name       = join("-", [local.policy_name, "policy-attachment"])
  roles      = var.use_existing_role ? [data.aws_iam_role.this[count.index].name] : [aws_iam_role.this[count.index].name]
  policy_arn = var.use_existing_policy ? data.aws_iam_policy.this[count.index].arn : aws_iam_policy.this[count.index].arn
}

data "aws_iam_policy" "this" {
  count = var.use_existing_policy ? 1 : 0
  arn   = var.policy_arn
}
