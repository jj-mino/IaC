/* ------------------------------ CLOUDWATCH  ------------------------------ */
## Allows worker nodes to send logs to Cloudwatch through CloudwatchAgent
resource "aws_iam_policy" "cloudwatchAgentLogsRetention" {
  name        = "${terraform.workspace}-cloudwatchAgentLogsRetention"
  description = "Allow to set a retention to existing CloudWatch Agent log group"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:PutRetentionPolicy"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/cloudwatchAgent:*"
    },
    {
      "Action": [
        "elasticfilesystem:DescribeMountTargets"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}


/* ------------------------------ EFS  ------------------------------ */
resource "aws_iam_policy" "efs" {
  # https://github.com/kubernetes-sigs/aws-efs-csi-driver?tab=readme-ov-file#using-botocore-to-retrieve-mount-target-ip-address-when-dns-name-cannot-be-resolved
  name        = "${terraform.workspace}-efs"
  description = "Allow worker nodes to look for EFS mount target IPs"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "elasticfilesystem:DescribeMountTargets",
        "ec2:DescribeAvailabilityZones"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}