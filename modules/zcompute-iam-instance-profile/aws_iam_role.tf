data "aws_iam_policy_document" "role" {
  version = "2012-10-17"
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count                 = var.use_existing_role ? 0 : 1
  name                  = local.role_name
  path                  = var.role_path
  force_detach_policies = true
  assume_role_policy    = var.role_contents != null ? jsonencode(var.role_contents) : data.aws_iam_policy_document.role.json

  #Not supported by zCompute
  #tags = var.tags
  depends_on = [aws_iam_policy.this, data.aws_iam_policy.this]
}


data "aws_iam_role" "this" {
  count = var.use_existing_role ? 1 : 0
  name  = local.role_name
}
