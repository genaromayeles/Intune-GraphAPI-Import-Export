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
        [string]$policyId,
        [string]$token
    )

    # Get the policy's last modified date using Graph API
    $uri = "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies/$policyId"
    #$policyResponse = Invoke-RestMethod -Uri $uri -Headers @{ "Authorization" = "Bearer $token" } -Method Get
    $policyResponse = Invoke-RestMethod -Headers $HeaderParams -Uri $uri -Method Get
    $policyModifiedDate = [datetime]$policyResponse.lastModifiedDateTime

    if (Test-Path -Path $filePath) {
        # Get the file's last modified date
        $fileModifiedDate = (Get-Item -Path $filePath).LastWriteTime

        if ($fileModifiedDate -ge $policyModifiedDate) {
            Write-Log "File already exists with matching modification date: $filePath"
            Write-Host "File already exists with matching modification date, skipping: $filePath" -ForegroundColor DarkMagenta
            return $true
        }
        else {
            Write-Log "File modification date differs from policy: $filePath"
            Write-Host "File modification date differs from policy, processing: $filePath" -ForegroundColor DarkYellow
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

######################
# ClientSecret       #
######################

# Retrieve encrypted client secret from file
try {
    $encryptedPassword = Get-Content -Path $credentialPath | ConvertTo-SecureString
    $client_Secret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($encryptedPassword))
}
catch {
    Write-Host "Failed to retrieve encrypted client secret. Please make sure client secret is in the appropriate location: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

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
# Export compliance policies to JSON #
######################################

$ExportFolderName = "CompliancePolicies"
$JSONLogFolder = "$logfolder\$ExportFolderName"
Ensure-FolderExists -folderPath "$JSONLogFolder"

try {
    $compliancePoliciesRequest = (Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies" -Method Get)
    $compliancePolicies = $compliancePoliciesRequest.value

    foreach ($policy in $compliancePolicies) {
        $filePath = "$($JSONLogFolder)\Compliance - $($policy.displayName).json"
        
        # Skip if file already exists with matching modification date
        if (Check-FileExistence -filePath $filePath -policyId $policy.id -token $HeaderParams.Authorization) { continue }
        
        # Retrieve full details including custom compliance settings
        $policyDetails = (Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies/$($policy.id)" -Method Get)
        
        # Check and include custom compliance elements if available
        if ($policyDetails.customCompliance) {
            $policyDetails.customComplianceSettings = @{
                status = $policyDetails.customCompliance.status
                discoveryScript = $policyDetails.customCompliance.discoveryScript
                customSettingsFile = $policyDetails.customCompliance.customSettingsFile
            }
        }
        
        # Export policy with custom settings if no duplicate exists
        $policyDetails | ConvertTo-Json -Depth 10 | Out-File $filePath
        Write-Log "Exported policy: $($policy.displayName) with custom compliance settings"
    }
}
catch {
    Write-Log "Error exporting compliance policies: $($_.Exception.Message)"
}

Write-Host "Compliance Policies with custom compliance settings successfully exported!" -ForegroundColor Green
