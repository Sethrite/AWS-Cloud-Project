<#
.SYNOPSIS
    Checks prerequisites that are needed to run the connection script; This starts off with
    helper functions that provide information and convert AWS's query system.

    Then, we install any of the prerequisites that are missing. Ex. AWS CLI & SSM Session Manager Plugin

    Then, we query for all the available clusters, services, and tasks that are open. Afterwards
    we open an interactive shell in the container via ECS Exec.
#>

# These are the parameters for the environment, allowed to be changed, but have defaults
param(
    [string]$Region = "us-east-2",
    [string]$Shell = "/bin/bash -c 'cd /home && /bin/bash'"
)

$ErrorActionPreference = "Stop"

# ------ Helper Functions ------ #

function Select-FromList {
    # Parameters given to the function for the selection logic
    param(
        [string]$Label,
        [string[]]$Items
    )

    # Sets the given list to the "Items" variable
    $Items = @($Items | Where-Object { $_ })

    # Special Case 1: No items found
    if ($Items.Count -eq 0) {
        Write-Host "No $Label found." -ForegroundColor Red
        exit 1
    }

    # Special Case 2: Only one item found, so just select that item. No need for choosing an option
    if ($Items.Count -eq 1) {
        Write-Host "Only one $Label found. Auto-selecting: $($Items[0])" -ForegroundColor Cyan
        return $Items[0]
    }

    # Normal Case: n amount of items found in the list, will scale up
    Write-Host "Multiple ${Label}s found. Please choose one:" -ForegroundColor Cyan

    # Display the options using formatting, 0 is the number and 1 is the item from the array
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host (" [{0}] {1}" -f ($i + 1), $Items[$i])
    }

    # Convert the string value to an integer, and if it is not within bounds ask again
    while ($true) {
        $choice = Read-Host "Enter selection number (1-$($Items.Count))"
        $n = 0
        if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) {
            return $Items[$n - 1]
        }
        Write-Host "Invalid choice." -ForegroundColor Yellow
    }
}

# Converts the tab-separated ARN text from the AWS CLI into short names/IDs
function ConvertFrom-ArnText {
    param([string]$ARNtext)

    # If there is no ARN text, return nothing
    if (-not $ARNtext) { return @() }

    # Else, split it by the white space and /'s
    $ARNtext -split '\s+' |
        Where-Object { $_ } |
        ForEach-Object { ($_ -split '/')[-1]}
}

function Test-AWSCredentials {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        aws sts get-caller-identity 2>$1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

# ------ Prerequisite: AWS CLI ------ #

# Path for the AWS CLI application
$awsDir = "C:\Program Files\Amazon\AWSCLIV2"

# Check if the aws command is in the environment variable path, else add it to path, else install the CLI
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    if (Test-Path (Join-Path $awsDir "aws.exe")) {
        $env:Path += ";$awsDir"
    }
    else {
        Write-Host "AWS CLI not found. Installing..." -ForegroundColor Yellow

        $msi = Join-Path $env:TEMP "AWSCLIV2.msi"
        Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $msi

        # Try to run the msi file as an administrator through this command
        try {
            # UAC prompt for the installer only
            Start-Process -FilePath "msiexec.exe" -ArgumentList "\i `"$msi`" /qn" -Verb RunAs -Wait
        }

        # If the elevation to administrator does not work, exit and ask for a manual install
        catch {
            Write-Host "Elevation was declined or failed. AWS CLI was not installed." -ForegroundColor Red
            exit 1
        }

        # Remove the variable everytime
        finally {
            Remove-Item $msi -ErrorAction SilentlyContinue
        }

        # Final check if the path works, and the command is found. Otherwise ask for a manual install
        $env:Path += ";$awsDir"
        if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
            Write-Host "AWS CLI install did not complete. Install it manually from https://aws.amazon.com/cli/ and re-run this program." -ForegroundColor Red
            exit 1        
        }
    }
}
Write-Host "AWS CLI OK." -ForegroundColor Green

# ------ Credential Check ------ #

# Check for aws credentials
if (-not (Test-AWSCredentials)) {
    Write-Host "No valid AWS credentials found." -ForegroundColor Yellow
    Write-Host "  [1] aws configure (access key / secret)"
    Write-Host "  [2] aws login      (browser sign-in)"
    $method = Read-Host "Choose a method (1-2)"

    if ($method -eq "2") { aws login}
    else                 { aws configure set region $Region; aws configure}

    # If the check fails, ask them to sign in or put in their api key
    if (-not (Test-AWSCredentials)) {
        Write-Host "Still no valid credentials. Check your keys and re-run this program." -ForegroundColor Red
        exit 1
    }
}

Write-Host "AWS Credentials OK." -ForegroundColor Green

# ------ Prerequisite: Session Manager Plugin ------ #

# Path for the Session Manager Plugin
$pluginDir = "C:\Program File\Amazon\SessionManagerPlugin\bin"

# Check if the aws command is in the environment variable path, else add it to path, else install the CLI
if (-not (Get-Command session-manager-plugin -ErrorAction SilentlyContinue)) {
    if (Test-Path (Join-Path $pluginDir "session-manager-plugin.exe")) {
        $env:Path += ";$pluginDir"
    }
    else {
        Write-Host "Session Manager plugin not found. Installing..." -ForegroundColor Yellow

        $installer = Join-Path $env:TEMP "SessionManagerPluginSetup.exe"
        Invoke-WebRequest -Uri "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe" -OutFile $installer

        # Try to run the exe file as an administrator through this command
        try {
            # UAC prompt for the installer only
            Start-Process -FilePath $installer -ArgumentList "/quiet" -Verb RunAs -Wait
        }

        # If the elevation to administrator does not work, exit and ask for a manual install
        catch {
            Write-Host "Elevation was declined or failed. The plugin was not installed." -ForegroundColor Red
            exit 1
        }

        # Remove the variable everytime
        finally {
            Remove-Item $installer -ErrorAction SilentlyContinue
        }

        # Final check if the path works, and the command is found. Otherwise ask for a manual install
        $env:Path += ";$pluginDir"
        if (-not (Get-Command session-manager-plugin -ErrorAction SilentlyContinue)) {
            Write-Host "AWS Session Manager plugin install did not complete. Install it manually from https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe and re-run this program." -ForegroundColor Red
            exit 1        
        }
    }
}
Write-Host "Session Manager Plugin OK." -ForegroundColor Green

# ------ Cluster Search ------ #

Write-Host "Looking up clusters in $Region..."
$clusterQuery = aws ecs list-clusters --region $Region --query "clusterArns[]" --output text
$cluster = Select-FromList -Label "cluster" -Items (ConvertFrom-ArnText $clusterQuery)
Write-Host "Cluster: $cluster" -ForegroundColor Green

# ------ Service Search ------ #

Write-Host "Looking up services in $cluster..."
$serviceQuery = aws ecs list-services --cluster $cluster --region $Region --query "serviceArns[]" --output text
$service = Select-FromList -Label "service" -Items (ConvertFrom-ArnText $serviceQuery)
Write-Host "Service: $service" -ForegroundColor Green

# Check for whether ECS Exec is enabled on the service
$execEnabled = aws ecs describe-services --cluster $cluster --services $service --region $Region `
    --query "services[0].enableExecuteCommand" --output text
if ($execEnabled -ne "True") {
    Write-Host "ECS Exec is not enabled on this service. Enable it with:" -ForegroundColor Yellow
    Write-Host "  aws ecs update-service --cluster $cluster --service $service --enable-execute-command --force-new-deployment --region $Region"
    exit 1
}

# ------ Choose Task ------ #

Write-Host "Looking up running tasks..."
$taskQuery = aws ecs list-tasks --cluster $cluster --service-name $service --desired-status RUNNING `
        --region $Region --query "taskArns[]" --output text
$task = Select-FromList -Label "running tasks" -Items (ConvertFrom-ArnText $taskQuery)
Write-Host "Task: $task" -ForegroundColor Green

# ------ Choose Container ------ #

$containerQuery = aws ecs describe-tasks --cluster $cluster --tasks $task --region $Region `
        --query "tasks[0].containers[].name" --output text
$container = Select-FromList -Lable "container" -Items @($containerQuery -split '\s+')
Write-Host "Container: $container" -ForegroundColor Green

# ------ Connecting to the ECS Environment ------ #

Write-Host "Connecting to ECS..."
Write-Host "----------------------------------------"
Write-Host "*** Type exit to leave the container ***" -ForegroundColor Red
Write-Host "----------------------------------------"

# Final remote command with all parameters
aws ecs execute-command `
    --cluster $cluster `
    --task $task `
    --container $container `
    --interactive `
    --region $Region `
    --command $Shell