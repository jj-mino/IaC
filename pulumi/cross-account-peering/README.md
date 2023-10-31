# Introduction:

Creates VPC peering and update route tables/security groups

- Install Pulumi and dependencies

  ```shell
  # get pulumi
  curl -sSL https://get.pulumi.com | sh

  # Install Pulumi dependencies.
  python3 -m venv venv
  venv/bin/pip3 install -r requirements.txt
  ```

## Usage

# Initial Setup

The network connectivity deployment must be executed for every new cluster, in the account and region where the cluster is deployed.  
If it is executed in the region/account combination for the first time, do the following:

- Create AWS S3 bucket with object versioning enabled and attach below policy:

  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "ForceSSLOnlyAccess",
        "Effect": "Deny",
        "Principal": "*",
        "Action": "s3:*",
        "Resource": [
          "arn:aws:s3:::<bucketname>/*",
          "arn:aws:s3:::<bucketname>"
        ],
        "Condition": {
          "Bool": {
            "aws:SecureTransport": "false"
          }
        }
      }
    ]
  }
  ```

- Create a new stack file

  ```shell
  # Login to AWS:
  export AWS_PROFILE="PROFILE-NAME"
  aws sso login

  # [Optional] Export variable to suppress pulumi asking for this value.
  export PULUMI_CONFIG_PASSPHRASE=""

  # Login to the state bucket (via `AWS_PROFILE`)
  export AWS_PROFILE="PROFILE-NAME"
  pulumi login s3://<bucketname>

  # Select stack
  pulumi stack init <dev>
  ```

- Add required variables to the newly create stack file.
  ```yaml
  config:
    aws:region: "us-west-2"
    network-aws:vpc_source:
    network-aws:vpcs_destination:
  ```

# Deploy

```shell
# Login to AWS:
export AWS_PROFILE="PROFILE-NAME"
aws sso login

# Create following env vars for AWS Providers
export AWS_PROFILE_NAME_PROFILE1="profile_name"
export AWS_PROFILE_NAME_PROFILE2="profile_name"

# [Optional] Export variable to suppress pulumi asking for this value.
export PULUMI_CONFIG_PASSPHRASE=""

# Login to the state bucket (via `AWS_PROFILE`)
export AWS_PROFILE="PROFILE-NAME"
pulumi login s3://<bucketname>

# Select stack
pulumi stack select <dev>

# Deploy/Update
pulumi up
```
