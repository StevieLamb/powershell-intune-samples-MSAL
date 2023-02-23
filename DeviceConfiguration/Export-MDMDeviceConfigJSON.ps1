
<#
    .SYNOPSIS
    Export all MDM config profiles from Intune as JSON
    Modified version of script found at
    https://github.com/microsoftgraph/powershell-intune-samples/blob/master/DeviceConfiguration/DeviceConfiguration_Import_FromJSON.ps1

    .DESCRIPTION
    The script will exporet all existing config profiles from Intune to a given folder
    This version uses the MSAL via MSAL.PS, rather than ADAL which will be discontinued soon.
    It alsos therefore avoids the AzureAD/AzureADPreview modules

    Requires:
    MSAL.PS module (available from PSGalery)
    An App Registration in the M365 tenant's Azure AD, with the following:
    MS Graph API permission, type Application: DeviceManagementConfiguration.ReadWrite.All
    A certificate keypair: must be installed on machine running script, and its public key added to the app
    under Certificates and secrets

    .PARAMETER ExportPath
    The path to export all configuration profiles to

    .PARAMETER tenant
    The target tenant

    .PARAMETER AppId
    The AppID or clientID of the App Registration to use

    .PARAMETER certThumbprint
    The thumbprint of the certificate associated with the application
    This certificate must be installed in the user's Personal >> Certificates store on the
    computer running the script

    .EXAMPLE
    $TargetFolder = "C:\temp\MDMConfigs"
    Export-MDMDeviceConfigJSON.ps1 -ExportPath $TargetFolder -tenant contoso.com -AppId "0000-0000000-0000000-00000" -certThumbprint AHG4587JDHFNMMN587MNSJHJFMN48762MN
    Stores the path to a target directory, then connects to the tenant by its default DNS domain using a pre-registered App Reg and certificate, and downloads all current MDM configs as JSON files
#>

####################################################

[cmdletbinding()]
param (
    [Parameter(Mandatory=$false)]
    [String]
    $ExportPath,

    [Parameter(Mandatory=$false)]
    [String]
    $tenant,

    [Parameter(Mandatory=$false)]
    [String]
    $AppId,

    [Parameter(Mandatory=$false)]
    [String]
    $certThumbprint
)

function MSALAuth {
    
    <#
        .SYNOPSIS
        Helper function to generate and return on MS Graph auth header using MSAL.PS
        The associated token will have the API permissions assigned to the service principal
        (i.e. the App Registration)
        Requires the module MSAL.PS
        
        .PARAMETER tenantID
        Default is WL tenant
        The tenant ID or DNS name of the tenant to target

        .PARAMETER clientID
        Default iS the id for "WL ID and Collab API-Based reporting"
        The ID of the application to use

        .PARAMETER thumbprint
        The thumbprint of the certificate associated with the application
        This certificate must be installed in the user's Personal >> Certificates store on the
        computer running the script

    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $tenantID,

        [Parameter(Mandatory=$true)]
        [string]
        $clientID,

        [Parameter(Mandatory=$true)]
        [string]
        $thumbprint
    )
    
    # Set path to certificate
    $path = "Cert:\CurrentUser\My\" + $thumbprint
    
    # Set up token request
    $connectionDetails = @{
        'TenantId'          = $tenantID
        'ClientId'          = $clientID
        'ClientCertificate' = Get-Item -Path $path
    }

    $token = Get-MsalToken @connectionDetails

    # prepare auth header for main query
    $MSALAuthHeader = @{
        'Authorization' = $token.CreateAuthorizationHeader()
    }

    return $MSALAuthHeader
}

####################################################

Function Get-DeviceConfigurationPolicy(){

<#
.SYNOPSIS
This function is used to get device configuration policies from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any device configuration policies
.EXAMPLE
Get-DeviceConfigurationPolicy
Returns any device configuration policies configured in Intune
.NOTES
NAME: Get-DeviceConfigurationPolicy
#>

[cmdletbinding()]

$graphApiVersion = "v1.0"
$DCP_resource = "deviceManagement/deviceConfigurations"
    
    try {
    
    $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)"
    (Invoke-RestMethod -Uri $uri -Headers $AuthHeader -Method Get).Value
    
    }
    
    catch {

    $ex = $_.Exception
    $errorResponse = $ex.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($errorResponse)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd();
    Write-Host "Response content:`n$responseBody" -f Red
    Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
    write-host
    break

    }

}

####################################################

Function Export-JSONData(){

<#
.SYNOPSIS
This function is used to export JSON data returned from Graph
.DESCRIPTION
This function is used to export JSON data returned from Graph
.EXAMPLE
Export-JSONData -JSON $JSON
Export the JSON inputted on the function
.NOTES
NAME: Export-JSONData
#>

param (

$JSON,
$ExportPath

)

    try {

        if($JSON -eq "" -or $JSON -eq $null){

            write-host "No JSON specified, please specify valid JSON..." -f Red

        }

        elseif(!$ExportPath){

            write-host "No export path parameter set, please provide a path to export the file" -f Red

        }

        elseif(!(Test-Path $ExportPath)){

            write-host "$ExportPath doesn't exist, can't export JSON Data" -f Red

        }

        else {

            $JSON1 = ConvertTo-Json $JSON -Depth 5

            $JSON_Convert = $JSON1 | ConvertFrom-Json

            $displayName = $JSON_Convert.displayName

            # Updating display name to follow file naming conventions - https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247%28v=vs.85%29.aspx
            $DisplayName = $DisplayName -replace '\<|\>|:|"|/|\\|\||\?|\*', "_"

            $FileName_JSON = "$DisplayName" + "_" + $(get-date -f dd-MM-yyyy-H-mm-ss) + ".json"

            write-host "Export Path:" "$ExportPath"

            $JSON1 | Set-Content -LiteralPath "$ExportPath\$FileName_JSON"
            write-host "JSON created in $ExportPath\$FileName_JSON..." -f cyan
            
        }

    }

    catch {

    $_.Exception

    }

}

####################################################

#region Authentication

$AuthHeader = MSALAuth -tenantID $tenant -clientID $AppId -thumbprint $certThumbprint

#endregion

####################################################

if (!$ExportPath) {
    $ExportPath = Read-Host -Prompt "Please specify a path to export the policy data to e.g. C:\IntuneOutput"
}
    # If the directory path doesn't exist prompt user to create the directory
    $ExportPath = $ExportPath.replace('"','')

    if(!(Test-Path "$ExportPath")){

    Write-Host
    Write-Host "Path '$ExportPath' doesn't exist, do you want to create this directory? Y or N?" -ForegroundColor Yellow

    $Confirm = read-host

        if($Confirm -eq "y" -or $Confirm -eq "Y"){

        new-item -ItemType Directory -Path "$ExportPath" | Out-Null
        Write-Host

        }

        else {

        Write-Host "Creation of directory path was cancelled..." -ForegroundColor Red
        Write-Host
        break

        }

    }

####################################################

Write-Host

# Filtering out iOS and Windows Software Update Policies
$DCPs = Get-DeviceConfigurationPolicy | Where-Object { ($_.'@odata.type' -ne "#microsoft.graph.iosUpdateConfiguration") -and ($_.'@odata.type' -ne "#microsoft.graph.windowsUpdateForBusinessConfiguration") }
foreach($DCP in $DCPs){

write-host "Device Configuration Policy:"$DCP.displayName -f Yellow
Export-JSONData -JSON $DCP -ExportPath "$ExportPath"
Write-Host

}

Write-Host
