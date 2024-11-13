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
# Export Assignment Filters #
######################################

try {
    $assignmentFiltersRequest = (Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters" -Method Get)
    $assignmentFilters = $assignmentFiltersRequest.value

    foreach ($filter in $assignmentFilters) {
        $filePath = "$($logfolder)\AssignmentFilter - $($filter.displayName).json"
        
        # Skip if file already exists
        if (Check-FileExistence -filePath $filePath) { continue }
        
        # Retrieve full details of the assignment filter
        $filterDetails = (Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($filter.id)" -Method Get)
        
        # Export filter with all details if no duplicate exists
        $filterDetails | ConvertTo-Json -Depth 10 | Out-File $filePath
        Write-Log "Exported Assignment Filter: $($filter.displayName)"
    }
}
catch {
    Write-Log "Error exporting Assignment Filters: $($_.Exception.Message)"
}

Write-Host "Assignment Filters successfully exported!" -ForegroundColor Yellow

######################################
# Additional Export Sections (Compliance Policies, Scripts, etc.) #
######################################

# (Existing sections for exporting compliance policies, device compliance scripts, device health scripts, configuration policies, ADMX files, migration reports, etc., would go here as in your original script.)
