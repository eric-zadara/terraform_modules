resource "aws_lb_target_group" "kube_api" {
  name        = "${substr(var.cluster_name, 0, 32 - 5)}-kapi"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.this.id
  target_type = "instance"
}

resource "aws_lb_listener" "k8s_api_listener" {
  load_balancer_arn = aws_lb.kube_api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kube_api.arn
  }
}

resource "aws_lb" "kube_api" {
  name               = "${substr(var.cluster_name, 0, 32 - 5)}-kapi"
  internal           = true
  load_balancer_type = "network"
  security_groups    = [aws_security_group.k8s.id]
  subnets            = var.subnets

  enable_deletion_protection = false

  tags = local.tags
}
