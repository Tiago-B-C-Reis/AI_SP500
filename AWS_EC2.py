import boto3
import botocore.exceptions

ec2_client = boto3.client('ec2')


ec2_client.create_security_group(
    "group_name": "launch-wizard-1",
    "description": "launch-wizard-1 created 2025-12-26T15:00:49.352Z",
    "vpc_id": "vpc-0b721dcd00d9a3eeb"
)


ec2_client.authorize_security_group_ingress(
    "group_id": "sg-preview-1",
    "ip_permissions": [{"ip_protocol": "tcp", "from_port": 22, "to_port": 22, "ip_ranges": [{"cidr_ip": "89.181.210.207/32"}]}]
)


ec2_client.run_instances(
    "max_count": 1,
    "min_count": 1,
    "image_id": "ami-0fa91bc90632c73c9",
    "instance_type": "m6i.4xlarge",
    "key_name": "TReis_EC2",
    "ebs_optimized": true,
    "block_device_mappings": [{"device_name": "/dev/sda1", "ebs": {"encrypted": false, "delete_on_termination": true, "iops": 3000, "snapshot_id": "snap-0ef1ff7e9d78a3771", "volume_size": 30, "volume_type": "gp3", "throughput": 125}}],
    "network_interfaces": [{"associate_public_ip_address": true, "device_index": 0, "groups": ["sg-preview-1"]}],
    "metadata_options": {"http_endpoint": "enabled", "http_put_response_hop_limit": 2, "http_tokens": "required"},
    "private_dns_name_options": {"hostname_type": "ip-name", "enable_resource_name_dns_arecord": true, "enable_resource_name_dns_aaaarecord": false}
)
