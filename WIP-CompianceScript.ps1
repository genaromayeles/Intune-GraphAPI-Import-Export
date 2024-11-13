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
    $ConnectGraph = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenant_Id/oauth2/token?api-version=1.0" -Method POST -Body $Body
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

###########################
# Import Compliance Scripts #
###########################

Write-Log "Retrieving existing compliance scripts from Intune..."
try {
    # Retrieve existing compliance scripts
    $existingScriptsRequest = Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceComplianceScripts" -Method Get
    $existingScriptNames = $existingScriptsRequest.value | ForEach-Object { $_.displayName }
    Write-Log "Successfully retrieved existing compliance scripts."
}
catch {
    Write-Log "Error retrieving existing compliance scripts: $($_.Exception.Message)"
    exit
}

# Loop through each JSON file with "ComplianceScript" in its name
try {
    foreach ($script in Get-ChildItem -Path "$location\ComplianceScript*" -File) {
        # Load JSON file
        $scriptContent = Get-Content -Path $script.FullName -Raw | ConvertFrom-Json
        $scriptName = $scriptContent.displayName

        # Check if script already exists
        if ($existingScriptNames -contains $scriptName) {
            Write-Log "Compliance Script '$scriptName' already exists. Skipping import."
            continue
        }

        # Validate required fields
        if (-not $scriptContent.displayName) {
            Write-Log "Missing displayName for $($script.FullName). Skipping import."
            continue
        }
        if (-not $scriptContent.detectionScriptContent) {
            Write-Log "Missing detectionScriptContent for $($script.FullName). Skipping import."
            continue
        }

        # Encode detectionScriptContent as Base64 if it exists
        $scriptContent.detectionScriptContent = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($scriptContent.detectionScriptContent))

        # Remove read-only fields that cannot be included in the import request
        $scriptContent.PSObject.Properties.Remove("id")
        $scriptContent.PSObject.Properties.Remove("createdDateTime")
        $scriptContent.PSObject.Properties.Remove("lastModifiedDateTime")
        $scriptContent.PSObject.Properties.Remove("version")

        # Convert to JSON for API submission
        $scriptJSON = $scriptContent | ConvertTo-Json -Depth 10


        # Import the compliance script
        try {
            $response = Invoke-RestMethod -Headers $HeaderParams -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceComplianceScripts" -Method POST -ContentType "application/json" -Body $scriptJSON
            Write-Log "Successfully imported compliance script: $scriptName"
        }
        catch {
            Write-Log "Error importing compliance script '$scriptName': $($_.Exception.Message)"
            if ($_.Exception.Response -and $_.Exception.Response.Content) {
                $errorContent = $_.Exception.Response.Content | ConvertFrom-Json
                Write-Log "Detailed error response for '$scriptName': $($errorContent | ConvertTo-Json -Depth 10)"
            }
        }
    }
}
catch {
    Write-Log "Error reading compliance scripts from ${location}: $($_.Exception.Message)"
}

Write-Host "Compliance Scripts import process completed!" -ForegroundColor Yellow
