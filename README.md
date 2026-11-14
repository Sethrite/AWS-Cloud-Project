<h1 align="center", >
    ML-Based Implementation of a Real-Time Cloud Intrusion Detection and Prevention System in AWS ECS
</h1>

# Project Overview
This project deploys an automated security pipeline on Amazon Web Services (AWS) Elastic Container Service (ECS) designed to detect runtime threats and isolate compromised containers without terminating them. It compares AWS native detection against an unsupervised machine learning model for detection speed and accuracy. Containment is handled via AWS Lambda and EventBridge, utilizing EC2 Security Group swapping to quarantine network traffic for forensic preservation.

# Tech Stack
Environment: AWS ECS & ECR \
Attack Simulation: Python/Boto3 (Attack Lambda) \
Detection: AWS GuardDuty & Scikit-learn Random Forest \
Telemetry: CloudTrail, VPC Flow Logs, CloudWatch \
Remediation: AWS EventBridge & Python/Boto3 (Isolation Lambda)

# Structure
├── attack-lambda-function/     **Python source code for the simulated attacker** \
├── ecr-setup/                   **Elastic Container Registry setup** \
├── isolation-lambda-function/  **Python source code for the automated quarantine** \
├── jupyter-ml-script/          **Jupyter source code and setup script along with testing data** \
├── session-manager-testing     **Testing scripts to remote into the ECS environment** \
├── .gitignore                   **Git configuration** \
└── README.md                   **Project documentation** 

# Prerequisites
- AWS CLI
- AWS Session Manager Plugin
- Docker or Docker Desktop
- Jupyter

# Evaluation Metrics
The pipeline's performance is measured using timestamps extracted from CloudWatch:

Time to Detect (TTD): T(detect) −T(attack_start) \
​Time to Isolate (TTI): T(quarantine)​ −T(detect) \
Total Exposure Time (MTTR): TTD + TTI

Includes all my tests for setting up the AWS environment, and files used for Lambdas.
This was used for ECS integration

# Setup Environment

## Elastic Container Registry (ECR) setup
Search for "**Elastic Container Registry**" in the AWS Search bar \
Then, follow the instructions below:
### Create a Repository in AWS
- Give the repository a name, ex: [accountid].dkr.ecr.[region].amazonaws.com/"**repo-name**"
- Make the repository **mutable**
- Set the encription configuration to **AES-256**
- Create the repository

### Push the Dockerfile to Repository
- Inside the newly-created repository, click "**View push commands**"
- In the **push commands** use the appropriate OS instructions and follow them using the **ecr-setup** directory
- After pushing the image to the repository, make sure the image is tagged with "latest"

## Elastic Container Service (ECS) setup
Search for "**Elastic Container Service**" in the AWS Search bar \
Then, follow the instructions below:
### Create an ECS Cluster
- Give the cluster a name, ex: "**Test-Cloud-Environment**"
- Set the Infrastructure to "**Fargate only**"
- Set the Monitoring as "**Container Insights with enhanced observability**"
- Leave everything else as default and click "**Create**"

### Create the Task definition
- On the sidebar of ECS, click on **Task definitions**
- Now create a "**Create new task definition**""
- Give the Task definition a "**Task definition family name**", ex: "Company-Simulation"
- Set the Launch type to "**AWS Fargate**"
- Set the Operating System to "**Linux/X86_64**"
- Set the CPU to 1vCPU & the Memory to 3 GB
- Under the Task roles section, in Task role click "**Create a new role**"
    - Click "**Use existing policy**" and select "**AmazonECS_FullAccess**"
    - Click "**Create role**", then in the search bar look up "**Roles**" within IAM and edit the newly created role 
    - Click "**Add permissions**" and "**Create an inline policy**", with the following configuration:
        ```
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "ssmmessages:CreateControlChannel",
                        "ssmmessages:CreateDataChannel",
                        "ssmmessages:OpenControlChannel",
                        "ssmmessages:OpenDataChannel"
                    ],
                    "Resource": "*"
                }
            ]
        }
        ```
        ** This is required to use the session manager **
- Under Task execution role, click "**Create a new role**"
    - There should already be an "**AmazonECSTaskExecutionRolePolicy**" added, if not add it as an existing policy
- Inside **Container - 1**, name the container and leave it as an essential container
- Click "**Browse ECR images**"
    - Select the repository you created before
    - Now select the image tagged **latest**, leave the selection on "**Image digest**"
    - Then, click "**Select image**"
- Set the **Container port** as 2222, with the "**Protocol**" as **TCP** and give the "**Port name**" "sshd-port" with the "**App protocol**" as **HTTP**
- Make sure **Log collection** is turned on and select the destination as "**Amazon CloudWatch**"
    - Specify any specific awslog locations you need, but otherwise leave the defaults
- Leave everything else as default and click "**Create**"

### Create the Service
- On the "**Services tab**", Click the "**Create**" button
- Select the Task definition you just created
- Give the Service a "**Service name**"
- Under Environment set the **Compute options** as "**Launch type**" and leave it on "**Fargate**" and "**LATEST**" as **Launch type** and **Platform version**
- **Important**: Make sure under **Troubleshooting configuration** you set it to "**Turn on ECS Exec**" - This is how we will enter the containers
- Set however many tasks you want for the **Desired tasks**, usually 3 tasks
- Under **Networking**, click "**Create a new VPC**" - This will bring you to the VPC service
    - In the **VPC settings**, select "**VPC only**" - We do not need additional availability zones
    - Then select the **Name tag**, set it to something like "ecs-vpc"
    - Leave the **IPv4 CIDR block** aat manual input
    - Now set the **IPv4 CIDR** to 172.31.0.0/16
    - Leave everything else as the default
    - Click "**Create VPC**"
- Choose the **available subnets**
- Under **Security group** select "**Create a new security group**"
    - This security group will only need egress or outbound rules, so remove any inbound rules for now
    - Name the security group something like "ecs-security-group"
    - Leave Public IP turned on
- Leave everything else as the default and click "**Create**"

## Lambda setup
Search for "**Lambda**" in the AWS Search bar \
Then, follow the instructions below:

- For each of the lambda functions we will use the same procedure, but change the input code for the lambda function
    - These will use the **attack-lambda-function**, and **isolation-lambda-function** directories
### Create the Lambda Function
- Click "**Create Event Function**"
- Leave it as **Author from Scratch**
- Give the function a **Function name**, ex: "**attack-lambda**"
- Set the **Runtime** to **Python 3.12**
- Leave everything else as the default and click "**Create Event Function**"

### Upload a Python script
- Inside a created **Lambda**, click the "**Update**" button, and choose the option "**Update from a .zip file**"
- Choose a directory with the **lambda-function code** in it and compress it into a **.zip file**
- Click the "**Choose file**" button and select the "**.zip**" file with the lambda code, ex: "**isolation-lambda-function.zip**"
- Leave **Encryption with an AWS KMS customer managed key** as off
- Click "**Update**"

### Update a Lambda Function
- After providing the "**.zip**" file with the code
- Move all of the files outside of the zip folder
- Then, delete the empty zip folder
- Click "**Deploy**" to make sure the code is pushed to AWS

### Setup the Attack Lambda Test
- Inside a created **Lambda**, click the **Test** tab and select "**Create a new event**"
- Under **Invocation type** select **Synchronous**
- Give the test an **Event name**, ex: "**execute-payload**"
- Set the **Event sharing settings** to "**Shareable**"
- Clear the **EVENT JSON** and leave it as "**{}**"
- Now click "**Save**" and "**Test**" - In the future, select "execute-payload" as the **saved event** 

## Setup Jupyter Test
- Using the following link: https://jupyter.org/try-jupyter/lab/?path=notebooks%2FIntro.ipynb, upload the **jupyter-ml-script** directory
- Place the logs (named logs.csv) and the detection.ipynb in the same folder, and then run the cells in order, on the website provided
- After running for the first time, you can comment classifiers in/out in cell 4 to run the one you want to test