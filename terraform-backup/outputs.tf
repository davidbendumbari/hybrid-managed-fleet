output "bucket_name" {
  value = aws_s3_bucket.backup.id
}

output "instance_profile" {
  value = aws_iam_instance_profile.node.name
}
