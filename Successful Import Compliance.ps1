param(
    [Parameter(Mandatory = $true)]
    [String]$client_Id,
    [Parameter(Mandatory = $true)]
    [String]$client_Secret,
    [Parameter(Mandatory = $true)]
    [String]$tenant_Id,
    [Parameter(Mandatory = $true)]
    [String]$location
)

#########################
# Connect to Graph API  #
#########################

$Body = @{    
    grant_type    = "client_credentials"
    resource      = "https://graph.microsoft.com"
    client_id     = $client_Id
    client_secret = $client_Secret
}

try {
    $ConnectGraph = Invoke-RestMethod -Uri "https://login.microsoft.com/$tenant_Id/oauth2/token?api-version=1.0" -Method POST -Body $Body
    Write-Host "Connected to Microsoft Graph API" -ForegroundColor Green
}
catch {
    Write-Host "Failed to connect to Microsoft Graph API: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

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
