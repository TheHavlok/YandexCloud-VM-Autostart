# =====================
# Yandex Cloud VM Autostart (PowerShell)
# =====================

# Configuration Paths (Shared with Python version)
$ConfigDir = "$HOME/.config/yandex-autostart"
$ConfigFile = "$ConfigDir/config.json"

# =====================
# LOGGING
# =====================
function Log-Info($msg) { 
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts [INFO] $msg" -ForegroundColor Cyan 
}
function Log-Ok($msg) { 
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts [OK] $msg" -ForegroundColor Green 
}
function Log-Warn($msg) { 
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts [WARN] $msg" -ForegroundColor Yellow 
}
function Log-Err($msg) { 
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts [ERROR] $msg" -ForegroundColor Red 
}

# =====================
# CONFIGURATION
# =====================
function Get-Config {
    if (Test-Path $ConfigFile) {
        try {
            return Get-Content -Raw $ConfigFile | ConvertFrom-Json
        } catch {
            Log-Err "Failed to parse config file."
            return $null
        }
    }
    return $null
}

function Save-Config($configObj) {
    if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null }
    $configObj | ConvertTo-Json -Depth 5 | Set-Content $ConfigFile
    Log-Ok "Config saved to $ConfigFile"
}

# =====================
# API CLIENT
# =====================
$Global:IAM_TOKEN = $null
$Global:OAUTH_TOKEN = $null

function Get-IamToken {
    if (-not $Global:OAUTH_TOKEN) { Log-Err "No OAuth token available"; throw "NoOAuth" }
    
    Log-Info "Refreshing IAM Token..."
    try {
        $body = @{ yandexPassportOauthToken = $Global:OAUTH_TOKEN } | ConvertTo-Json
        $resp = Invoke-RestMethod -Method Post -Uri "https://iam.api.cloud.yandex.net/iam/v1/tokens" -Body $body -ContentType "application/json"
        $Global:IAM_TOKEN = $resp.iamToken
        Log-Ok "IAM Token refreshed"
    } catch {
        Log-Err "Failed to refresh IAM token: $($_.Exception.Message)"
        throw
    }
}

function Invoke-YandexApi {
    param($Method="Get", $Uri, $Body=$null)
    
    if (-not $Global:IAM_TOKEN) { Get-IamToken }

    $headers = @{ Authorization = "Bearer $Global:IAM_TOKEN" }
    if ($Body) { $headers["Content-Type"] = "application/json" }

    try {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body $Body
    } catch {
        # Check for 401 Unauthorized
        if ($_.Exception.Response.StatusCode.value__ -eq 401) {
            Log-Warn "Token expired (401), refreshing..."
            try {
                Get-IamToken
                $headers["Authorization"] = "Bearer $Global:IAM_TOKEN"
                return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body $Body
            } catch {
                Log-Err "Retry failed: $($_.Exception.Message)"
                throw
            }
        } else {
            throw
        }
    }
}

# =====================
# ACTIONS
# =====================
function Check-And-Start($instanceId) {
    try {
        $inst = Invoke-YandexApi -Uri "https://compute.api.cloud.yandex.net/compute/v1/instances/$instanceId"
        $name = $inst.name
        $status = $inst.status

        if ($status -eq "RUNNING") {
            Log-Ok "$name is RUNNING"
        } elseif ($status -eq "STOPPED") {
            Log-Warn "$name is STOPPED -> Starting..."
            Invoke-YandexApi -Method Post -Uri "https://compute.api.cloud.yandex.net/compute/v1/instances/$instanceId:start" | Out-Null
            Log-Info "Start command sent"
        } else {
            Log-Info "$name status: $status"
        }
    } catch {
        Log-Err "Error checking instance: $($_.Exception.Message)"
    }
}

# =====================
# SETUP WIZARD
# =====================
function Run-Setup {
    Write-Host "`n=== Yandex Cloud Autostart Setup (PowerShell) ===" -ForegroundColor Cyan
    Write-Host "Obtain OAuth token here: https://yandex.cloud/ru/docs/iam/concepts/authorization/oauth-token`n"
    
    $oauth = Read-Host "Enter OAuth Token"
    $Global:OAUTH_TOKEN = $oauth.Trim()

    try {
        Get-IamToken
    } catch {
        Log-Err "Authentication failed."
        exit
    }

    # Pick Cloud
    $clouds = (Invoke-YandexApi -Uri "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/clouds").clouds
    Write-Host "`nAvailable Clouds:"
    for ($i=0; $i -lt $clouds.Count; $i++) { Write-Host " $($i+1)) $($clouds[$i].name)" }
    $cIdx = [int](Read-Host "Select Cloud [1]") - 1
    if ($cIdx -lt 0) { $cIdx = 0 }
    $cloudId = $clouds[$cIdx].id

    # Pick Folder
    $folders = (Invoke-YandexApi -Uri "https://resource-manager.api.cloud.yandex.net/resource-manager/v1/folders?cloudId=$cloudId").folders
    Write-Host "`nAvailable Folders:"
    for ($i=0; $i -lt $folders.Count; $i++) { Write-Host " $($i+1)) $($folders[$i].name)" }
    $fIdx = [int](Read-Host "Select Folder [1]") - 1
    if ($fIdx -lt 0) { $fIdx = 0 }
    $folderId = $folders[$fIdx].id

    # Pick Instance
    $instances = (Invoke-YandexApi -Uri "https://compute.api.cloud.yandex.net/compute/v1/instances?folderId=$folderId").instances
    if (-not $instances) { Log-Err "No instances found in folder"; exit }
    Write-Host "`nAvailable Instances:"
    for ($i=0; $i -lt $instances.Count; $i++) { Write-Host " $($i+1)) $($instances[$i].name) ($($instances[$i].id))" }
    $iIdx = [int](Read-Host "Select Instance [1]") - 1
    if ($iIdx -lt 0) { $iIdx = 0 }
    $instance = $instances[$iIdx]

    $config = @{
        oauth_token = $Global:OAUTH_TOKEN
        instance_id = $instance.id
        instance_name = $instance.name
        check_interval = 60
    }
    Save-Config $config
    Log-Ok "Setup complete. Run script again to start monitoring."
}

# =====================
# MAIN
# =====================
param([switch]$Setup)

if ($Setup) {
    Run-Setup
    exit
}

$config = Get-Config
if (-not $config) {
    Log-Warn "Configuration not found. Starting setup..."
    Run-Setup
    $config = Get-Config
}

$Global:OAUTH_TOKEN = $config.oauth_token
$instanceId = $config.instance_id
$interval = if ($config.check_interval) { $config.check_interval } else { 60 }

Log-Info "Starting Monitor for $($config.instance_name) ($instanceId)"
Log-Info "Interval: $interval seconds"

while ($true) {
    Check-And-Start $instanceId
    Start-Sleep -Seconds $interval
}
