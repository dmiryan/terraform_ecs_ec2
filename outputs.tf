output "load_balancer_ip" {
  value = aws_lb.default.dns_name
}

output "esc_agent_role_name" {
  value = aws_iam_role.ecs_agent.name
}
