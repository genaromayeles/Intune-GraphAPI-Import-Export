# Create logfile
$Purpose = "IntuneWorkloadSync"
$logfolder = "C:\Support\$Purpose"
$logFileName = (Get-Date -Format "yyyy-MM-dd_HH-mm")
$LogFile = "$logfolder\$logFileName.log"

# Hard-coded Client ID and Tenant ID
$client_Id = "9dc87879-a922-477b-85a7-e8509b49741f"
$tenant_Id = "f8ff6e6b-7337-47d6-8e7e-f961f8836708"
$location = "C:\Support\IntuneWorkloadSync"
$credentialPath = "$location\VUHLSecureClientSecret.txt"

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
# Export ADMX Files (Group Policy Uploaded Definition Files) #
######################################

try {
    $admxFilesRequest = (Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyUploadedDefinitionFiles" -Method Get)
    $admxFiles = $admxFilesRequest.value

    foreach ($admxFile in $admxFiles) {
        # Use displayName if available; fallback to id if not
        if ($admxFile.displayName) {
            $displayName = $admxFile.displayName -replace '[\\/:*?"<>|]', '_'
        }
        else {
            Write-Log "ADMX file has no displayName, using id as filename: $($admxFile.id)"
            $displayName = "ADMXFile_$($admxFile.id)"
        }

        # Set file path with sanitized name
        $filePath = "$($logfolder)\ADMX - $displayName.json"
        
        # Skip if file already exists
        if (Check-FileExistence -filePath $filePath) { continue }
        
        # Retrieve full details of the ADMX file
        $admxFileDetails = (Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/beta/deviceManagement/groupPolicyUploadedDefinitionFiles/$($admxFile.id)" -Method Get)
        
        # Export ADMX file details if no duplicate exists
        $admxFileDetails | ConvertTo-Json -Depth 10 | Out-File $filePath
        Write-Log "Exported ADMX File: $displayName"
    }
}
catch {
    Write-Log "Error exporting ADMX Files: $($_.Exception.Message)"
    
    # Additional logging for debugging
    if ($_.Exception.Response -and $_.Exception.Response.Content) {
        $errorContent = $_.Exception.Response.Content | ConvertFrom-Json
        Write-Log "Detailed error response: $($errorContent | ConvertTo-Json -Depth 5)"
    }
}

Write-Host "ADMX Files (Group Policy Uploaded Definition Files) successfully exported!" -ForegroundColor Yellow
