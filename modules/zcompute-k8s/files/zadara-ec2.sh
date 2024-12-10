#!/bin/sh
export AWS_ENDPOINT_URL=$(curl -s http://169.254.169.254/openstack/latest/meta_data.json | jq -c -r '.cluster_url')
export AWS_ENDPOINT_URL_EC2=${AWS_ENDPOINT_URL}/api/v2/aws/ec2/
#export AWS_ENDPOINT_URL_ELASTIC_LOAD_BALANCING=${AWS_ENDPOINT_URL}/api/v2/aws/elbv2/
export AWS_ENDPOINT_URL_ELASTIC_LOAD_BALANCING_V2=${AWS_ENDPOINT_URL}/api/v2/aws/elbv2/
export AWS_ENDPOINT_URL_AUTO_SCALING=${AWS_ENDPOINT_URL}/api/v2/aws/autoscaling/
export AWS_ENDPOINT_URL_CLOUDWATCH=${AWS_ENDPOINT_URL}/api/v2/aws/cloudwatch/
export AWS_ENDPOINT_URL_SNS=${AWS_ENDPOINT_URL}/api/v2/aws/sns/
export AWS_ENDPOINT_URL_IAM=${AWS_ENDPOINT_URL}/api/v2/aws/iam/
export AWS_ENDPOINT_URL_ROUTE_53=${AWS_ENDPOINT_URL}/api/v2/aws/route53/
export AWS_ENDPOINT_URL_ACM=${AWS_ENDPOINT_URL}/api/v2/aws/acm/
#export AWS_DEFAULT_REGION=us-east-1
