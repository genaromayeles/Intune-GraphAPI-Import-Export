# Create logfile
$Purpose = "IntuneWorkloadSync"
$logfolder = "C:\Support\$Purpose"
$logFileName = (Get-Date -Format "yyyy-MM-dd_HH-mm")
$LogFile = "$logfolder\$logFileName.log"

# Hard-coded Client ID and Tenant ID
$client_Id = "21fdd255eeshj66584aswe454563dddddeert"
$tenant_Id = "21fdd255eeshj66584aswe454563dddddeert"
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

# Check if the location exists
if (-not (Test-Path -Path $location)) {
    Write-Host "The specified location path does not exist: $location" -ForegroundColor Red
    exit
}

###########################
# Functions for Logging   #
###########################

function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Host $logMessage
}

#####################
# Import Compliance #
#####################

function Import-CompliancePolicies {
    param (
        [string]$policyPath
    )

    # Loop through each JSON file with "Compliance" in its name
    try {
        foreach ($policy in Get-ChildItem -Path "$policyPath\Compliance*") {
            # Convert JSON file to Hashtable to make it editable
            $JSON = [System.Collections.Hashtable]::new()
            $policyContent = Get-Content -Path $policy.FullName -Raw | ConvertFrom-Json
            $policyContent.PSObject.Properties | ForEach-Object {
                $JSON.Add($_.Name, $_.Value)
            }

            # Remove read-only fields that cannot be included in the import request
            $JSON.Remove("id")
            $JSON.Remove("createdDateTime")
            $JSON.Remove("lastModifiedDateTime")
            $JSON.Remove("version")

            # Add scheduledActionsForRule if not present
            if (-not $JSON.ContainsKey("scheduledActionsForRule")) {
                $JSON["scheduledActionsForRule"] = @(
                    @{
                        ruleName = "PasswordRequired"
                        scheduledActionConfigurations = @(
                            @{
                                actionType = "block"
                                gracePeriodHours = 0
                                notificationTemplateId = ""
                                notificationMessageCCList = @()
                            }
                        )
                    }
                )
            }

            # Convert Hashtable back to JSON for API submission
            $JSONBody = $JSON | ConvertTo-Json -Depth 10

            # Log the JSON content for debugging
            Write-Log "JSON Content for policy $($policy.Name): $JSONBody"

            # Import the compliance policy via the Graph API
            try {
                $response = Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies" -Method POST -ContentType "application/json" -Body $JSONBody
                $policyName = $JSON["displayName"]
                Write-Log "Successfully imported compliance policy: $policyName"
            }
            catch {
                Write-Log "Error importing compliance policy $($policy.Name): $($_.Exception.Message)"
                
                # Check for detailed error response
                if ($_.Exception.Response -and $_.Exception.Response.Content) {
                    $responseContent = $_.Exception.Response.Content | ConvertFrom-Json
                    Write-Log "Detailed error response for $($policy.Name): $($responseContent)"
                }
            }
        }
    }
    catch {
        Write-Log "Error reading compliance policies from ${policyPath}: $($_.Exception.Message)"
    }
}

# Call the function to import compliance policies
Import-CompliancePolicies -policyPath $location
