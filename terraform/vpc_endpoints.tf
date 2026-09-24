# EXERCISE REQUIREMENT (Outpost, Private Connectivity):
# a pod must be able to list and get objects from the backup bucket without
# traversing the public internet.
#
# A Gateway endpoint is the right shape for S3 here. It installs a prefix-list
# route into the route tables, so traffic to S3 leaves via the endpoint instead
# of the NAT gateway and the internet gateway. It costs nothing and carries no
# data charge, unlike an Interface endpoint.
#
# To prove it is actually in use, check that the private route table has a
# route to the S3 prefix list, and that the pod still reaches the bucket after
# the NAT gateway route is removed.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  # Private route table is what the EKS nodes use, so it is the one that
  # satisfies the requirement. The public table is included so the MongoDB
  # VM's nightly backup upload also stays off the internet gateway.
  route_table_ids = [
    aws_route_table.private.id,
    aws_route_table.public.id,
  ]

  tags = { Name = "${var.project}-s3" }
}
