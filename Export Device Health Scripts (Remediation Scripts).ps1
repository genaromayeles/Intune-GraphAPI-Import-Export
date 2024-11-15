# Create logfile
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

# Function to check if the file exists and modification date matches the policy's last modified date from Graph API
Function Check-FileExistence {
    Param (
        [string]$filePath,
        [string]$scriptId,
        [string]$token
    )

    # Get the policy's last modified date using Graph API
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts/$scriptId"
    #$policyResponse = Invoke-RestMethod -Uri $uri -Headers @{ "Authorization" = "Bearer $token" } -Method Get
    $scriptResponse = Invoke-RestMethod -Headers $HeaderParams -Uri $uri -Method Get
    $scriptModifiedDate = [datetime]$scriptResponse.lastModifiedDateTime

    if (Test-Path -Path $filePath) {
        # Get the file's last modified date
        $fileModifiedDate = (Get-Item -Path $filePath).LastWriteTime

        if ($fileModifiedDate -ge $scriptModifiedDate) {
            Write-Log "File already exists with matching modification date: $filePath"
            Write-Host "File already exists with matching modification date, skipping: $filePath" -ForegroundColor DarkMagenta
            return $true
        }
        else {
            Write-Log "File modification date differs from Remediation Script: $filePath"
            Write-Host "File modification date differs from Remediation scriptr, processing: $filePath" -ForegroundColor DarkYellow
            return $false
        }
    }
    return $false
}

function Ensure-FolderExists {
    param (
        [string]$folderPath
    )

    if (!(Test-Path -Path $folderPath)) {
        New-Item -ItemType Directory -Path $folderPath | Out-Null
        Write-Output "Folder created at $folderPath"  
    } else {
        Write-Output "Folder already exists at $folderPath"  
    }
}

#################
# Logging       #
#################

# Change to false to stop logging
$Log = $true

# Ensure log folder exists
Ensure-FolderExists -folderPath "$logfolder"
Ensure-FolderExists -folderPath "$logfolder\Logging"


# Ensure log file exists
if (-not (Test-Path -Path $LogFile)) {
    New-Item -ItemType File -Path $LogFile -Force
}

Write-Host "`nYour logging folder is located at: $logfolder" -ForegroundColor Green


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

###################################
# Export device compliance scripts#
###################################

$ExportFolderName = "Remediation Script"
$JSONLogFolder = "$logfolder\$ExportFolderName"
Ensure-FolderExists -folderPath "$JSONLogFolder"
try {
    $deviceHealthScriptsRequest = (Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts" -Method Get)
    $deviceHealthScripts = $deviceHealthScriptsRequest.value

    foreach ($script in $deviceHealthScripts) {
        $filePath = "$($JSONLogFolder)\DeviceHealthScript - $($script.displayName).json"
        
        # Skip if file already exists
        if (Check-FileExistence -filePath $filePath -scriptId $script.id -token $HeaderParams.Authorization) { continue }
  
        
        # Export filter with all details if no duplicate exists
        $script | ConvertTo-Json -Depth 10 | Out-File $filePath
        Write-Log "Exported Assignment Filter: $($script.displayName)"
    }
}
catch {
    Write-Log "Error exporting Remediation Script: $($_.Exception.Message)"
}

Write-Host "Remediation Script successfully exported!" -ForegroundColor Yellow
