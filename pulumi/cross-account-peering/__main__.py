import os
import pulumi
import pulumi_aws as aws
from pulumi import ResourceOptions, InvokeOptions

config = pulumi.Config()
vpc_source = config.require_object('vpc_source')
vpcs_destination = config.require_object('vpcs_destination')


profile1 = aws.Provider(resource_name="account_profile2",
                           region=vpc_source["region_name"],
                           profile=f"{os.environ['AWS_PROFILE_NAME_PROFILE1']}")

profile2 = aws.Provider(resource_name="account_profile1",
                           region=vpc_source["region_name"],
                           profile=f"{os.environ['AWS_PROFILE_NAME_PROFILE2']}")

providers = {
    "000000000000": profile1,
    "999999999999": profile2
}

source_aws_provider = providers[vpc_source["account_id"]]

for vpc_destination in vpcs_destination:

    destination_aws_provider = providers[vpc_destination["account_id"]]

    vpc_source_cidrs=[o.cidr_block for o in aws.ec2.get_vpc(opts=InvokeOptions(provider=source_aws_provider),id=vpc_source["vpc_id"]).cidr_block_associations]
    vpc_destination_cidrs=[o.cidr_block for o in aws.ec2.get_vpc(opts=InvokeOptions(provider=destination_aws_provider),id=vpc_destination["vpc_id"]).cidr_block_associations]

    vpc_peering_connection = aws.ec2.VpcPeeringConnection(
        resource_name=(f"create_peering_from_{vpc_source['vpc_id']}_to_{vpc_destination['vpc_id']}"),
        opts=ResourceOptions(provider=source_aws_provider, parent=source_aws_provider),
        peer_owner_id=vpc_destination["account_id"],
        peer_vpc_id=vpc_destination["vpc_id"],
        vpc_id=vpc_source["vpc_id"],
        tags={
            "Name": f"{vpc_source['vpc_id']}_to_{vpc_destination['vpc_id']}"
        }
    )

    vpc_peering_accepter_aws = aws.ec2.VpcPeeringConnectionAccepter(
        resource_name=(f"accept_peering_from_{vpc_source['vpc_id']}_in_{vpc_destination['vpc_id']}"),
        opts=ResourceOptions(provider=destination_aws_provider, parent=destination_aws_provider),
        vpc_peering_connection_id=vpc_peering_connection.id,
        auto_accept=True,
        tags={
            "Name": f"{vpc_destination['vpc_id']}_to_{vpc_source['vpc_id']}"
        }
    )

    for rtb_id in vpc_source["rtb_ids"]:
        for cidr in vpc_destination_cidrs:
            route = aws.ec2.Route(
                resource_name=(f"{rtb_id}_add_{cidr}"),
                opts=ResourceOptions(provider=source_aws_provider, parent=source_aws_provider),
                route_table_id=rtb_id,
                destination_cidr_block=cidr,
                vpc_peering_connection_id=vpc_peering_connection.id
            )

    for rtb_id in vpc_destination["rtb_ids"]:
        for cidr in vpc_source_cidrs:
            route = aws.ec2.Route(
                resource_name=(f"{rtb_id}_add_{cidr}"),
                opts=ResourceOptions(provider=destination_aws_provider, parent=destination_aws_provider),
                route_table_id=rtb_id,
                destination_cidr_block=cidr,
                vpc_peering_connection_id=vpc_peering_accepter_aws.id
            )

    if vpc_destination.get("security_groups") is not None:
        for security_group in vpc_destination["security_groups"]:
            # look for security group based on Name or id
            _security_group = aws.ec2.get_security_group(
                opts=InvokeOptions(provider=destination_aws_provider),
                id=security_group.get("security_group_id"),
                name=security_group.get("security_group_name")
            )

            for cidr in vpc_source_cidrs:
                security_group_rule=aws.ec2.SecurityGroupRule(
                    resource_name=f'allow {security_group["from_port"]}-{security_group["to_port"]} from {cidr} at {_security_group.id} ({_security_group.name})',
                    opts=ResourceOptions(provider=destination_aws_provider, parent=destination_aws_provider),
                    type=security_group.get("type", "ingress"),
                    from_port=security_group["from_port"],
                    to_port=security_group["to_port"],
                    protocol=security_group.get("protocol", "tcp"),
                    cidr_blocks=[cidr],
                    security_group_id=_security_group.id,
                    description=f'{vpc_source["name"]} vpc (aws account {vpc_source["account_id"]})'
                )

    aws.ec2.SecurityGroup(
        resource_name=(f"allow_{vpc_source['vpc_id']}_in_{vpc_destination['vpc_id']}"),
        opts=ResourceOptions(provider=destination_aws_provider, parent=destination_aws_provider),
        description=(f"allow access from {vpc_source['vpc_id']}"),
        vpc_id=vpc_destination["vpc_id"],
        ingress=[
            aws.ec2.SecurityGroupIngressArgs(
                description=f"Allow {vpc_source['vpc_id']}",
                from_port=0,
                to_port=0,
                protocol="-1",
                cidr_blocks=vpc_source_cidrs
            )
        ],
        tags={
            "Name": f"allow access from {vpc_source['vpc_id']}"
        }
    )
