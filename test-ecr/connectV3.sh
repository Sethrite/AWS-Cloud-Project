#!/bin/bash

# Only fixed variable: the region
REGION="us-east-2"

# Print a numbered menu and set CHOSEN to the selected item.
# Usage: choose "Label" item1 item2 ...
# Auto-selects when there is only one item. Menu text goes to stderr.
choose() {
    local label="$1"; shift
    local items=("$@")
    CHOSEN=""

    if [ ${#items[@]} -eq 0 ]; then
        echo "❌ Error: No $label found." >&2
        exit 1
    fi

    if [ ${#items[@]} -eq 1 ]; then
        CHOSEN="${items[0]}"
        echo "🎯 Only one $label found. Auto-selecting: $CHOSEN" >&2
        return
    fi

    echo "📋 Multiple ${label}s found. Please choose one:" >&2
    for i in "${!items[@]}"; do
        echo "  [$((i+1))] ${items[$i]}" >&2
    done

    local choice
    while true; do
        read -r -p "Enter selection number (1-${#items[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
            CHOSEN="${items[$((choice-1))]}"
            return
        fi
        echo "❌ Invalid choice. Please enter a number between 1 and ${#items[@]}." >&2
    done
}

# Turn tab-separated ARN output into one resource name/ID per line
# (strips the ARN prefix and any Windows carriage returns)
arns_to_names() {
    tr '\t' '\n' | tr -d '\r' | awk -F/ 'NF {print $NF}'
}

# 1. Cluster
echo "🔎 Looking up clusters in $REGION..."
mapfile -t CLUSTERS < <(aws ecs list-clusters \
    --region "$REGION" \
    --query 'clusterArns[]' \
    --output text | arns_to_names)
choose "cluster" "${CLUSTERS[@]}"
CLUSTER_NAME="$CHOSEN"
echo "✅ Cluster: $CLUSTER_NAME"

# 2. Service
echo "🔎 Looking up services in $CLUSTER_NAME..."
mapfile -t SERVICES < <(aws ecs list-services \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --query 'serviceArns[]' \
    --output text | arns_to_names)
choose "service" "${SERVICES[@]}"
SERVICE_NAME="$CHOSEN"
echo "✅ Service: $SERVICE_NAME"

# 3. Running tasks
echo "🔎 Looking up running tasks for $SERVICE_NAME..."
mapfile -t TASK_IDS < <(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --desired-status RUNNING \
    --region "$REGION" \
    --query 'taskArns[]' \
    --output text | arns_to_names)
choose "running task" "${TASK_IDS[@]}"
SELECTED_TASK_ID="$CHOSEN"
echo "🎯 Selected Task ID: $SELECTED_TASK_ID"

# 4. Container name for the chosen task
echo "🔎 Looking up container name..."
CONTAINER_NAME=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --tasks "$SELECTED_TASK_ID" \
    --query 'tasks[0].containers[0].name' \
    --output text | tr -d '\r')

if [ -z "$CONTAINER_NAME" ] || [ "$CONTAINER_NAME" == "None" ]; then
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