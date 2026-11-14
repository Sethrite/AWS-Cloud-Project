#!/bin/bash

# 1. Set your fixed variables here
CLUSTER_NAME="Test-Cloud-Environment"
SERVICE_NAME="Company-Simulation"
REGION="us-east-2" 

echo "🔎 Looking up active Fargate tasks in $REGION..."

# 2. Get a list of ALL running Task ARNs and convert them into raw Task IDs
# (Instead of picking just the first one, we store them all in a Bash array)
IFS=$'\n' read -r -d '' -a TASK_IDS < <(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --desired-status RUNNING \
    --region "$REGION" | jq -r '.taskArns[]' | awk -F/ '{print $NF}' && printf '\0')

# Check if any tasks were found
if [ ${#TASK_IDS[@]} -eq 0 ]; then
    echo "❌ Error: No running tasks found for service $SERVICE_NAME."
    exit 1
fi

# 3. Present an interactive menu to the user if multiple tasks exist
SELECTED_TASK_ID=""

if [ ${#TASK_IDS[@]} -eq 1 ]; then
    # If there is only 1 task running, skip the menu and auto-select it
    SELECTED_TASK_ID="${TASK_IDS[0]}"
    echo "🎯 Only one task running. Auto-selecting Task ID: $SELECTED_TASK_ID"
else
    echo "📋 Multiple running tasks found. Please choose one:"
    for i in "${!TASK_IDS[@]}"; do
        echo "  [$((i+1))] Task ID: ${TASK_IDS[$i]}"
    done

    # Loop until the user provides a valid numeric selection
    while true; do
        read -p "Enter selection number (1-${#TASK_IDS[@]}): " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#TASK_IDS[@]}" ]; then
            SELECTED_TASK_ID="${TASK_IDS[$((CHOICE-1))]}"
            break
        else
            echo "❌ Invalid choice. Please enter a number between 1 and ${#TASK_IDS[@]}."
        fi
    done
fi

echo "🎯 Selected Task ID: $SELECTED_TASK_ID"
echo "🔎 Looking up container name..."

# 4. Query the container name for the chosen task
CONTAINER_NAME=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --tasks "$SELECTED_TASK_ID" | jq -r '.tasks[].containers[].name' | head -n 1)

if [ -z "$CONTAINER_NAME" ] || [ "$CONTAINER_NAME" == "null" ]; then
    echo "❌ Error: Could not resolve container name for task $SELECTED_TASK_ID."
    exit 1
fi

echo "📦 Found Container: $CONTAINER_NAME"
echo "🚀 Connecting to container via /bin/bash..."
echo "----------------------------------------"

# 5. Execute the final command
MSYS_NO_PATHCONV=1 aws ecs execute-command \
    --cluster "$CLUSTER_NAME" \
    --task "$SELECTED_TASK_ID" \
    --container "$CONTAINER_NAME" \
    --interactive \
    --region "$REGION" \
    --command "/bin/bash -c 'cd /home && /bin/bash'"
