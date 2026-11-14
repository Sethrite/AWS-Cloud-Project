#!/bin/bash

# 1. Set your fixed variables here
CLUSTER_NAME="Test-Cloud-Environment"
SERVICE_NAME="user1"

echo "🔎 Looking up active Fargate tasks..."

# 2. Automatically query the latest Running Task ID
TASK_ID=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --desired-status RUNNING | jq -r '.taskArns[0]' | awk -F/ '{print $NF}')

if [ -z "$TASK_ID" ] || [ "$TASK_ID" == "null" ]; then
    echo "❌ Error: No running tasks found for service $SERVICE_NAME."
    exit 1
fi

echo "🎯 Found Task ID: $TASK_ID"
echo "🔎 Looking up container name..."

# 3. Automatically query the first container name in that task
CONTAINER_NAME=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$TASK_ID" \
    | jq -r '.tasks[0].containers[0].name')

echo "📦 Found Container: $CONTAINER_NAME"
echo "🚀 Connecting to container..."
echo "----------------------------------------"

# 4. Execute the command (with the Git Bash path fix included)
MSYS_NO_PATHCONV=1 aws ecs execute-command \
    --cluster "$CLUSTER_NAME" \
    --task "$TASK_ID" \
    --container "$CONTAINER_NAME" \
    --interactive \
    --command "/bin/bash"
