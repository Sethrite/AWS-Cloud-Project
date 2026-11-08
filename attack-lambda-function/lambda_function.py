import json
import os
import shlex
import subprocess

import boto3

REGION = os.environ.get("AWS_REGION", "us-east-2")
PLUGIN = os.environ.get("SSM_PLUGIN_PATH", "/opt/bin/session-manager-plugin")
COMMANDS_FILE = os.path.join(os.path.dirname(__file__), "payload.json")

ecs = boto3.client("ecs", region_name=REGION)


def load_payload():
    with open(COMMANDS_FILE) as f:
        return json.load(f)


def pick_target_container():
    """Pick the container we will run the payload over and target"""
    cluster_arn = ecs.list_clusters()["clusterArns"][0]
    service_arn = ecs.list_services(cluster=cluster_arn)["serviceArns"][0]
    task_arn = ecs.list_tasks(cluster=cluster_arn, serviceName=service_arn, desiredStatus="RUNNING")["taskArns"][0]

    task = ecs.describe_tasks(cluster=cluster_arn, tasks=[task_arn])["tasks"][0]
    # Pick the first container whose ExecuteCommandAgent is running
    for container in task["containers"]:
        for agent in container.get("managedAgents", []):
            if agent["name"] == "ExecuteCommandAgent" and agent["lastStatus"] == "RUNNING":
                return cluster_arn, service_arn, task_arn, container["name"]
    raise RuntimeError("No container in the task has a RUNNING ExecuteCommandAgent yet.")


def start_session(cluster, task_arn, container, command, timeout=300):
    resp = ecs.execute_command(
        cluster=cluster,
        task=task_arn,
        container=container,
        interactive=True,
        command=command,
    )
    session = resp["session"]
    task_id = task_arn.split("/")[-1]
    cluster_name = cluster.split("/")[-1]
    target = f"ecs:{cluster_name}_{task_id}_{container}"

    # The API only hands back a websocket URL + token. The session-manager-plugin
    # binary opens it, runs the command, collects output, and exits when the
    # command finishes. No shell is left open.
    process = subprocess.run(
        [
            PLUGIN,
            json.dumps(session),
            REGION,
            "StartSession",
            "",
            json.dumps({"Target": target}),
            f"https://ssm.{REGION}.amazonaws.com",
        ],
        capture_output=True,
        text=True,
        timeout=timeout,
        cwd="/tmp",
        env={**os.environ, "HOME": "/tmp"},
    )
    return process.returncode, process.stdout, process.stderr


def lambda_handler(event, context):
    payload = load_payload()
    cluster, service, task_arn, container = pick_target_container()
    print(json.dumps({"cluster": cluster, "service": service,
                      "task": task_arn, "container": container}))

    results = []
    for command in payload["commands"]:
        wrapped = f"/bin/bash -c {shlex.quote(command)}"

        exit_code, output, error = start_session(cluster, task_arn, container, wrapped)
        results.append({"command": command, "exit_code": exit_code, "output": output, "stderr": error})
        print(json.dumps(results[-1]))

        if exit_code != 0 and payload.get("stop_on_failure", True):
            break

    return {"cluster": cluster, "service": service, "task": task_arn,
            "container": container, "results": results}