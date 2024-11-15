# Create logfile
$Purpose = "IntuneWorkloadSync"
$logfolder = "C:\Support\$Purpose"
$logFileName = (Get-Date -Format "yyyy-MM-dd_HH-mm")
$LogFile = "$logfolder\Logging\$logFileName.log"

# Hard-coded Client ID and Tenant ID
$client_Id = "sjsjdsksd3sd23s2s55s1s1sd44d1d14d44d"
$tenant_Id = "22sd54d5df44h55j622w4d1dd12zaq5w2e2e0f"
$credentialPath = "$logfolder\VUHLSecureClientSecret.txt"

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
    $uri = "https://graph.microsoft.com/beta/deviceManagement/deviceComplianceScripts/$scriptId"
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
            Write-Log "File modification date differs from script: $filePath"
            Write-Host "File modification date differs from script, processing: $filePath" -ForegroundColor DarkYellow
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

$ExportFolderName = "ComplianceScript"
$JSONLogFolder = "$logfolder\$ExportFolderName"
Ensure-FolderExists -folderPath "$JSONLogFolder"
try {
    $complianceScriptsRequest = (Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceComplianceScripts" -Method Get)
    $complianceScripts = $complianceScriptsRequest.value

    foreach ($script in $complianceScripts) {
        $filePath = "$($JSONLogFolder)\ComplianceScript - $($script.displayName).json"
        
        # Skip if file already exists
        if (Check-FileExistence -filePath $filePath -scriptId $script.id -token $HeaderParams.Authorization) { continue }
        
        # Export script if no duplicate exists
        $script | ConvertTo-Json -Depth 10 | Out-File $filePath
        Write-Log "Exported compliance script: $($script.displayName)"
    }
}
catch {
    Write-Log "Error exporting compliance scripts: $($_.Exception.Message)"
}

Write-Host "Device Compliance Scripts successfully exported!" -ForegroundColor Yellow
