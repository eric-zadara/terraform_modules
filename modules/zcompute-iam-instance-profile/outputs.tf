output "instance_profile_name" {
  description = "In 22.09.x the launch configuration expecting the unique id and not the instance profile name."
  value       = aws_iam_instance_profile.this.unique_id
}
#output "debug" {
#  value = data.aws_iam_policy_document.policy.json
#}
