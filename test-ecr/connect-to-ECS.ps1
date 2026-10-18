<#
.SYNOPSIS
  Checks prerequisites, then lets you pick a cluster, service and task
  and opens an interactive shell in the container via ECS Exec.
#>

param(
    [string]$Region = "us-east-2",
    [string]$Shell  = "/bin/bash -c 'cd /home && /bin/bash'"
)

$ErrorActionPreference = "Stop"

# ---------- Helpers ----------

function Select-FromList {
    param(
        [string]$Label,
        [string[]]$Items
    )
    $Items = @($Items | Where-Object { $_ })
    if ($Items.Count -eq 0) {
        Write-Host "No $Label found." -ForegroundColor Red
        exit 1
    }
    if ($Items.Count -eq 1) {
        Write-Host "Only one $Label found. Auto-selecting: $($Items[0])" -ForegroundColor Cyan
        return $Items[0]
    }
    Write-Host "Multiple ${Label}s found. Please choose one:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $Items[$i])
    }
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
    param([string]$Text)
    if (-not $Text) { return @() }
    $Text -split '\s+' |
        Where-Object { $_ } |
        ForEach-Object { ($_ -split '/')[-1] }
}

# ---------- Prerequisite: AWS CLI ----------

$awsDir = "C:\Program Files\Amazon\AWSCLIV2"

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    if (Test-Path (Join-Path $awsDir "aws.exe")) {
        $env:Path += ";$awsDir"
    }
    else {
        Write-Host "AWS CLI not found. Installing..." -ForegroundColor Yellow

        $msi = Join-Path $env:TEMP "AWSCLIV2.msi"
        Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $msi

        try {
            # UAC prompt for the installer only
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msi`" /qn" -Verb RunAs -Wait
        }
        catch {
            Write-Host "Elevation was declined or failed. AWS CLI was not installed." -ForegroundColor Red
            exit 1
        }
        finally {
            Remove-Item $msi -ErrorAction SilentlyContinue
        }

        $env:Path += ";$awsDir"
        if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
            Write-Host "AWS CLI install did not complete. Install it manually from https://aws.amazon.com/cli/ and re-run." -ForegroundColor Red
            exit 1
        }
    }
}
Write-Host "AWS CLI OK." -ForegroundColor Green

# ---------- Credentials ----------

aws sts get-caller-identity *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "No valid AWS credentials found." -ForegroundColor Yellow
    Write-Host "  [1] aws configure  (access key / secret)"
    Write-Host "  [2] aws login      (browser sign-in)"
    $method = Read-Host "Choose a method (1-2)"

    if ($method -eq "2") { aws login }
    else                 { aws configure set region $Region; aws configure }

    aws sts get-caller-identity *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Still no valid credentials. Check your keys and re-run." -ForegroundColor Red
        exit 1
    }
}
Write-Host "AWS credentials OK." -ForegroundColor Green

# ---------- Prerequisite: Session Manager plugin ----------

$pluginDir = "C:\Program Files\Amazon\SessionManagerPlugin\bin"

if (-not (Get-Command session-manager-plugin -ErrorAction SilentlyContinue)) {
    if (Test-Path (Join-Path $pluginDir "session-manager-plugin.exe")) {
        $env:Path += ";$pluginDir"
    }
    else {
        Write-Host "Session Manager plugin not found. Installing..." -ForegroundColor Yellow

        $isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $isAdmin) {
            Write-Host "Installing the plugin needs an elevated PowerShell. Re-run as Administrator." -ForegroundColor Red
            exit 1
        }

        $installer = Join-Path $env:TEMP "SessionManagerPluginSetup.exe"
        $url = "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe"
        Invoke-WebRequest -Uri $url -OutFile $installer

        try {
            # Triggers the UAC prompt for just the installer
            Start-Process -FilePath $installer -ArgumentList "/quiet" -Verb RunAs -Wait
        }
        catch {
            Write-Host "Elevation was declined or failed. The plugin was not installed." -ForegroundColor Red
            exit 1
        }
        finally {
            Remove-Item $installer -ErrorAction SilentlyContinue
        }

        $env:Path += ";$pluginDir"
    }
}
Write-Host "Session Manager plugin OK." -ForegroundColor Green

# ---------- Cluster ----------

Write-Host "Looking up clusters in $Region..."
$text = aws ecs list-clusters --region $Region --query "clusterArns[]" --output text
$cluster = Select-FromList -Label "cluster" -Items (ConvertFrom-ArnText $text)
Write-Host "Cluster: $cluster" -ForegroundColor Green

# ---------- Service ----------

Write-Host "Looking up services in $cluster..."
$text = aws ecs list-services --cluster $cluster --region $Region --query "serviceArns[]" --output text
$service = Select-FromList -Label "service" -Items (ConvertFrom-ArnText $text)
Write-Host "Service: $service" -ForegroundColor Green

# ECS Exec must be enabled on the service
$execEnabled = aws ecs describe-services --cluster $cluster --services $service --region $Region `
    --query "services[0].enableExecuteCommand" --output text
if ($execEnabled -ne "True") {
    Write-Host "ECS Exec is not enabled on this service. Enable it with:" -ForegroundColor Yellow
    Write-Host "  aws ecs update-service --cluster $cluster --service $service --enable-execute-command --force-new-deployment --region $Region"
    exit 1
}

# ---------- Task ----------

Write-Host "Looking up running tasks..."
$text = aws ecs list-tasks --cluster $cluster --service-name $service --desired-status RUNNING `
    --region $Region --query "taskArns[]" --output text
$task = Select-FromList -Label "running task" -Items (ConvertFrom-ArnText $text)
Write-Host "Task: $task" -ForegroundColor Green

# ---------- Container ----------

$text = aws ecs describe-tasks --cluster $cluster --tasks $task --region $Region `
    --query "tasks[0].containers[].name" --output text
$container = Select-FromList -Label "container" -Items @($text -split '\s+')
Write-Host "Container: $container" -ForegroundColor Green

# ---------- Connect ----------

Write-Host "Connecting..." -ForegroundColor Cyan
Write-Host "----------------------------------------"

Write-Host "*** Type exit to leave the container ***" -ForegroundColor Red
Write-Host "----------------------------------------"

aws ecs execute-command `
    --cluster $cluster `
    --task $task `
    --container $container `
    --interactive `
    --region $Region `
    --command $Shell