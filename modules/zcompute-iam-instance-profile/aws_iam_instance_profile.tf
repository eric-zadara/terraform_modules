resource "aws_iam_instance_profile" "this" {
  name       = var.name
  path       = var.instance_profile_path
  role       = var.use_existing_role ? data.aws_iam_role.this[0].name : aws_iam_role.this[0].name
  depends_on = [aws_iam_policy_attachment.this, aws_iam_role.this, data.aws_iam_role.this]
}
