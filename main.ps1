# =====================
# CONFIGURATION
# =====================
$CREDENTIALS_FILE = "$HOME\.yc_autostart_credentials"
$CHECK_INTERVAL = 60

# Defaults
$INSTANCE_ID = "your-instance-id-here"
$IAM_TOKEN = "your-iam-token-here"

# =====================
# COLORS
# =====================
function Write-OK($text){ Write-Host $text -ForegroundColor Green }
function Write-WARN($text){ Write-Host $text -ForegroundColor Yellow }
function Write-ERR($text){ Write-Host $text -ForegroundColor Red }
function Write-INFO($text){ Write-Host $text -ForegroundColor Cyan }
function Write-DIM($text){ Write-Host $text -ForegroundColor DarkGray }

function Log($msg){
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-DIM "$ts $msg"
}

# =====================
# CREDENTIALS
# =====================
function Load-Credentials {
    if (Test-Path $CREDENTIALS_FILE) {
        Get-Content $CREDENTIALS_FILE | ForEach-Object {
            if ($_ -match '^INSTANCE_ID="(.+)"') { $global:INSTANCE_ID = $matches[1] }
            if ($_ -match '^IAM_TOKEN="(.+)"') { $global:IAM_TOKEN = $matches[1] }
        }
        Log "Credentials loaded from $CREDENTIALS_FILE"
    } else {
        Log "No credentials file found, using globals"
    }
}

function Save-Credentials {
    @"
INSTANCE_ID="$INSTANCE_ID"
IAM_TOKEN="$IAM_TOKEN"
"@ | Set-Content $CREDENTIALS_FILE
    Log "Credentials saved to $CREDENTIALS_FILE"
}

# =====================
# API FUNCTIONS
# =====================
function Exchange-OAuthToIAM($oauth){
    $body = @{ yandexPassportOauthToken = $oauth } | ConvertTo-Json
    $resp = Invoke-RestMethod -Method Post -Uri "https://iam.api.cloud.yandex.net/iam/v1/tokens" -Body $body -ContentType "application/json"
    $global:IAM_TOKEN = $resp.iamToken
}

function Get-Clouds { 
    Invoke-RestMethod -Uri "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds" -Headers @{ Authorization = "Bearer $IAM_TOKEN" } | Select-Object -ExpandProperty clouds
}

function Get-Folders($cloudId){ 
    Invoke-RestMethod -Uri "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/folders?cloudId=$cloudId" -Headers @{ Authorization = "Bearer $IAM_TOKEN" } | Select-Object -ExpandProperty folders
}

function Get-Instances($folderId){ 
    Invoke-RestMethod -Uri "https://compute.api.cloud.yandex.net/compute/v1/instances?folderId=$folderId" -Headers @{ Authorization = "Bearer $IAM_TOKEN" } | Select-Object -ExpandProperty instances
}

# =====================
# SELECT HELPERS
# =====================
function Select-ItemInteractive($items, $label){
    if ($items.Count -eq 1) { return $items }
    Write-Host "`nAvailable $label:"
    for ($i=0; $i -lt $items.Count; $i++){
        $item = $items[$i]
        Write-Host " $($i+1)) $($item.name) " -NoNewline; Write-OK $item.id
    }
    $choice = Read-Host "`nSelect number or press Enter for ALL [default: all]"
    if (-not $choice -or $choice -eq 0) { return $items }
    return @($items[$choice-1])
}

# =====================
# GETMYINFO
# =====================
function Get-MyInfo {
    Write-Host "`nYandex Cloud authorization required"
    Write-OK "https://yandex.cloud/ru/docs/iam/concepts/authorization/oauth-token"
    $oauth = Read-Host "Paste OAuth token"
    if (-not $oauth) { Write-ERR "OAuth token is empty"; exit 1 }

    Log "Exchanging OAuth → IAM"
    Exchange-OAuthToIAM $oauth
    Write-OK "IAM token received"

    $clouds = Select-ItemInteractive (Get-Clouds) "Clouds"
    $allInstances = @()
    foreach ($cloud in $clouds){
        Log "Processing Cloud $($cloud.name)"
        $folders = Select-ItemInteractive (Get-Folders $cloud.id) "Folders"
        foreach ($folder in $folders){
            Log "Fetching instances from folder $($folder.name)"
            $instances = Get-Instances $folder.id
            foreach ($inst in $instances){
                $inst | Add-Member -NotePropertyName Cloud -NotePropertyValue $cloud.name
                $inst | Add-Member -NotePropertyName Folder -NotePropertyValue $folder.name
            }
            $allInstances += $instances
        }
    }

    # Show available instances
    Write-Host "`nAvailable instances:"
    foreach ($inst in $allInstances){
        $pre = $inst.schedulingPolicy.preemptible
        $pflag = if ($pre) { Write-OK "YES" } else { Write-WARN "NO" }
        Write-Host $inst.name
        Write-Host "  ID:           $($inst.id)"
        Write-Host "  Preemptible:  $pflag"
        Write-Host "  Cloud:        $($inst.Cloud)"
        Write-Host "  Folder:       $($inst.Folder)"
        Write-Host ""
    }

    Write-Host "================================================================"
    Write-Host "CONFIGURATION SUMMARY"
    Write-Host "IAM_TOKEN = $IAM_TOKEN"
    Write-Host "Available instances:"
    foreach ($inst in $allInstances){
        Write-Host $inst.name
        Write-Host "  ID:           $($inst.id)"
    }

    $save = Read-Host "Do you want to save IAM_TOKEN and INSTANCE_ID to file for future runs? [y/N]"
    if ($save -match '^[Yy]$'){
        if ($allInstances.Count -eq 1){
            $global:INSTANCE_ID = $allInstances[0].id
        } else {
            Write-Host "`nSelect INSTANCE_ID to save:"
            for ($i=0; $i -lt $allInstances.Count; $i++){
                Write-Host " $($i+1)) $($allInstances[$i].name) " -NoNewline; Write-OK $($allInstances[$i].id)
            }
            $choice = Read-Host "Select number [default 1]"
            $choice = if ($choice) { $choice-1 } else { 0 }
            $global:INSTANCE_ID = $allInstances[$choice].id
        }
        Save-Credentials
    }
}

# =====================
# MONITORING
# =====================
function Start-Instance {
    $url = "https://compute.api.cloud.yandex.net/compute/v1/instances/$INSTANCE_ID:start"
    $resp = Invoke-RestMethod -Method Post -Uri $url -Headers @{ Authorization = "Bearer $IAM_TOKEN"; "Content-Type" = "application/json" }
    Log "Start command sent"
}

function Check-InstanceStatus {
    $url = "https://compute.api.cloud.yandex.net/compute/v1/instances/$INSTANCE_ID"
    $resp = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $IAM_TOKEN" }
    $status = $resp.status
    $name = $resp.name
    Write-Host "Instance: $name (ID: $INSTANCE_ID)"
    Write-Host "Status: $status"
    if ($status -eq "RUNNING"){ Write-OK "✓ Instance is RUNNING" }
    elseif ($status -eq "STOPPED"){ Write-WARN "⚠ Instance is STOPPED → starting"; Start-Instance }
    else { Write-INFO "⏳ Instance status: $status" }
    Write-Host "------------------------------------------------------------"
}

# =====================
# MAIN
# =====================
param([switch]$getmyinfo)

Load-Credentials

if ($getmyinfo){ Get-MyInfo; exit }

if ($INSTANCE_ID -like "your-*" -or $IAM_TOKEN -like "your-*"){ Write-ERR "INSTANCE_ID and IAM_TOKEN must be set or saved in $CREDENTIALS_FILE"; exit 1 }

Write-Host "Starting instance status monitoring with auto-start..."
Write-Host "Instance ID: $INSTANCE_ID"
Write-Host "Check interval: $CHECK_INTERVAL seconds"
Write-Host "============================================================"

try{
    while ($true){
        Check-InstanceStatus
        Start-Sleep -Seconds $CHECK_INTERVAL
    }
} catch [System.Management.Automation.StopUpstreamCommandsException] {
    Write-WARN "Monitoring stopped by user"
}
