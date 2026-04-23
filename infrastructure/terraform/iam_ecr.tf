resource "aws_iam_user_policy_attachment" "ecr_power_user" {
  user       = "fiapcloudgames"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}
