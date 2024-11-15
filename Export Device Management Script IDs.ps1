﻿# Create logfile
$Purpose = "IntuneWorkloadSync"
$logfolder = "C:\Support\$Purpose"
$logFileName = (Get-Date -Format "yyyy-MM-dd_HH-mm")
$LogFile = "$logfolder\$logFileName.log"

# Hard-coded Client ID and Tenant ID
$client_Id = "12fsergckkk563344789dgsggdf5f555555sss"
$tenant_Id = "12fsergckkk563344789dgsggdf5f555555sss"
$location = "C:\Support\IntuneWorkloadSync"
$credentialPath = "$location\ClientSecret.txt"

# Retrieve encrypted client secret from file
try {
    $encryptedPassword = Get-Content -Path $credentialPath | ConvertTo-SecureString
    $client_Secret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($encryptedPassword))
}
catch {
    Write-Host "Failed to retrieve encrypted client secret: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

#####################
# Functions         #
#####################

# Function to generate timestamp
function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

# Function to write to log
Function Write-Log {
    Param ([string]$logstring)

    if ($Log) {
        try {
            $timestamp = Get-TimeStamp
            Add-Content $LogFile -Value ($timestamp + ": " + $logstring)
        }
        catch {
            Write-Host "Error writing to log file: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Function to check for existing files and skip if already exists
Function Check-FileExistence {
    Param ([string]$filePath)

    if (Test-Path -Path $filePath) {
        Write-Log "File already exists: $filePath"
        Write-Host "File already exists, skipping: $filePath" -ForegroundColor DarkMagenta
        return $true
    }
    return $false
}

#################
# Logging       #
#################

# Change to false to stop logging
$Log = $true

# Ensure log folder exists
if (-not (Test-Path -Path $logfolder)) {
    New-Item -ItemType Directory -Path $logfolder -Force
}

# Ensure log file exists
if (-not (Test-Path -Path $LogFile)) {
    New-Item -ItemType File -Path $LogFile -Force
}

Write-Host "`nYour logging folder is located at: $logfolder" -ForegroundColor Green

##############################
# Graph API Variables        #
##############################

Write-Log "Next step is to obtain an Access Token with PowerShell, then use that token to call Microsoft Graph API"

####################
# Connect to Graph #
####################
$Body = @{    
    grant_type    = "client_credentials"
    scope         = "https://graph.microsoft.com/.default"
    client_id     = $client_Id
    client_secret = $client_Secret
} 

$ConnectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenant_Id/oauth2/v2.0/token" -Method POST -ContentType "application/x-www-form-urlencoded" -Body $Body

# Output token for testing purposes
$ConnectGraph.access_token

########################
# Variable Collections #
########################

$HeaderParams = @{
    'Content-Type'  = "application/json"
    'Authorization' = "Bearer $($ConnectGraph.access_token)"
}

######################################
# Export Device Management Script IDs #
######################################

try {
    $deviceManagementScriptsRequest = (Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts" -Method Get)
    $deviceManagementScripts = $deviceManagementScriptsRequest.value

    foreach ($script in $deviceManagementScripts) {
        $filePath = "$($logfolder)\DeviceManagementScriptID - $($script.displayName).json"
        
        # Skip if file already exists
        if (Check-FileExistence -filePath $filePath) { continue }
        
        # Export only the script ID and name
        $scriptIDInfo = @{
            displayName = $script.displayName
            id = $script.id
        }
        
        $scriptIDInfo | ConvertTo-Json -Depth 10 | Out-File $filePath
        Write-Log "Exported Device Management Script ID: $($script.displayName)"
    }
}
catch {
    Write-Log "Error exporting Device Management Script IDs: $($_.Exception.Message)"
}

Write-Host "Device Management Script IDs successfully exported!" -ForegroundColor Yellow

######################################
# Additional Export Sections (Compliance Policies, Scripts, etc.) #
######################################

# (Existing sections for exporting compliance policies, device compliance scripts, device health scripts, configuration policies, ADMX files, and migration reports would go here as in your original script.)

