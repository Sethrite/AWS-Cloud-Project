import json
import logging
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

REGION = "us-east-2"
ecs = boto3.client("ecs", region_name=REGION)
ec2 = boto3.client("ec2", region_name=REGION)

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    
    cluster_arn = event.get("clusterArn")
    task_arn = event.get("taskArn")
    
    if not cluster_arn or not task_arn:
        logger.error("Missing clusterArn or taskArn. Aborting.")
        return {"status": "error", "message": "Cluster or Task ARN missing"}

    try:
        # 1. Inspect the running ECS Task to find its attached network interface
        task_desc = ecs.describe_tasks(cluster=cluster_arn, tasks=[task_arn])
        tasks = task_desc.get("tasks", [])
        if not tasks:
            return {"status": "error", "message": "Task not found."}

        eni_id = None
        for attachment in tasks[0].get("attachments", []):
            if attachment.get("type") == "ElasticNetworkInterface":
                for detail in attachment.get("details", []):
                    if detail.get("name") == "networkInterfaceId":
                        eni_id = detail.get("value")
                        break

        if not eni_id:
            return {"status": "error", "message": "No ENI found for the specified task."}

        logger.info(f"Identified ENI: {eni_id}")

        # 2. Get the Security Group(s) currently attached to this ENI
        eni_desc = ec2.describe_network_interfaces(NetworkInterfaceIds=[eni_id])
        groups = eni_desc["NetworkInterfaces"][0].get("Groups", [])
        
        if not groups:
            return {"status": "error", "message": "No security groups attached to ENI."}

        # 3. Strip all inbound and outbound rules in-place
        quarantined_groups = []
        for group in groups:
            sg_id = group["GroupId"]
            logger.info(f"Stripping rules from Security Group: {sg_id}")

            sg_details = ec2.describe_security_groups(GroupIds=[sg_id])["SecurityGroups"][0]
            ingress_rules = sg_details.get("IpPermissions", [])
            egress_rules = sg_details.get("IpPermissionsEgress", [])

            # Revoke inbound rules if any exist
            if ingress_rules:
                ec2.revoke_security_group_ingress(
                    GroupId=sg_id,
                    IpPermissions=ingress_rules
                )
                logger.info(f"Revoked inbound rules for {sg_id}")

            # Revoke outbound rules if any exist
            if egress_rules:
                ec2.revoke_security_group_egress(
                    GroupId=sg_id,
                    IpPermissions=egress_rules
                )
                logger.info(f"Revoked outbound rules for {sg_id}")

            quarantined_groups.append(sg_id)

        return {
            "status": "success",
            "message": f"Successfully isolated ENI {eni_id} by stripping rules from security groups.",
            "quarantined_security_groups": quarantined_groups
        }

    except Exception as e:
        logger.error(f"Error executing isolation: {str(e)}")
        raise e