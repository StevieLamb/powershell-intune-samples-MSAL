<#
    .SYNOPSIS
    Creates a new Intune device configuration profile from a JSON file
    Modified version of script found at
    https://github.com/microsoftgraph/powershell-intune-samples/blob/master/DeviceConfiguration/DeviceConfiguration_Import_FromJSON.ps1

    .DESCRIPTION
    This version uses the MSAL via MSAL.PS, rather than ADAL which will be discontinued soon.
    It alsos therefore avoids the AzureAD/AzureADPreview modules

    Requires:
    MSAL.PS module (available from PSGalery)
    An App Registration in the M365 tenant's Azure AD, with the following:
    MS Graph API permission, type Application: DeviceManagementConfiguration.ReadWrite.All
    A certificate keypair: must be installed on machine running script, and its public key added to the app
    under Certificates and secrets

    .PARAMETER FileName
    The path and name of the JSON file representation of the configuration profile

    .PARAMETER tenant
    The target tenant

    .PARAMETER AppId
    The AppID or clientID of the App Registration to use

    .PARAMETER certThumbprint
    The thumbprint of the certificate associated with the application
    This certificate must be installed in the user's Personal >> Certificates store on the
    computer running the script

    .EXAMPLE
    $JSONFile = "C:\temp\newMDMProfile.json"
    Import-MDMDeviceConfigJSON.ps1 -filename $JSONFile -tenant contoso.com -AppId "0000-0000000-0000000-00000" -certThumbprint AHG4587JDHFNMMN587MNSJHJFMN48762MN
    Stores the path to a JSON file, then connects to the tenant by its default DNS domain using a pre-registered App Reg and certificate
#>

[cmdletbinding()]
param (
    [Parameter(Mandatory=$false)]
    [String]
    $FileName,

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

####################################################

function MSALAuth {
    
    <#
        .SYNOPSIS
        Helper function to generate and return on MS Graph auth header using MSAL.PS
        The associated token will have the API permissions assigned to the service principal
        (i.e. the App Registration)
        Requires the module MSAL.PS
        
        .PARAMETER tenantID
        The tenant ID or DNS name of the tenant to target

        .PARAMETER clientID
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

Function Add-DeviceConfigurationPolicy(){

<#
.SYNOPSIS
This function is used to add an device configuration policy using the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and adds a device configuration policy
.EXAMPLE
Add-DeviceConfigurationPolicy -JSON $JSON
Adds a device configuration policy in Intune
.NOTES
NAME: Add-DeviceConfigurationPolicy
#>

[cmdletbinding()]

param
(
    $JSON
)

$graphApiVersion = "v1.0"
$DCP_resource = "deviceManagement/deviceConfigurations"
Write-Verbose "Resource: $DCP_resource"

    try {

        if($JSON -eq "" -or $JSON -eq $null){

        write-host "No JSON specified, please specify valid JSON for the Device Configuration Policy..." -f Red

        }

        else {

        Test-JSON -JSON $JSON

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($DCP_resource)"
        Invoke-RestMethod -Uri $uri -Headers $AuthHeader -Method Post -Body $JSON -ContentType "application/json"

        }

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

Function Test-JSON(){

<#
.SYNOPSIS
This function is used to test if the JSON passed to a REST Post request is valid
.DESCRIPTION
The function tests if the JSON passed to the REST Post is valid
.EXAMPLE
Test-JSON -JSON $JSON
Test if the JSON is valid before calling the Graph REST interface
.NOTES
NAME: Test-AuthHeader
#>

param (

$JSON

)

    try {

    $TestJSON = ConvertFrom-Json $JSON -ErrorAction Stop
    $validJson = $true

    }

    catch {

    $validJson = $false
    $_.Exception

    }

    if (!$validJson){
    
    Write-Host "Provided JSON isn't in valid JSON format" -f Red
    break

    }

}

####################################################

#region Authentication

$AuthHeader = MSALAuth -tenantID $tenant -clientID $AppId -thumbprint $certThumbprint

#endregion

####################################################

If (Test-Path -Path $FileName -Type Leaf) {
	$ImportPath = $FileName
} Else {
	$ImportPath = Read-Host -Prompt "Please specify a path to a JSON file to import data from e.g. C:\IntuneOutput\Policies\policy.json"
}

# Replacing quotes for Test-Path
$ImportPath = $ImportPath.replace('"','')

if(!(Test-Path "$ImportPath")){

Write-Host "Import Path for JSON file doesn't exist..." -ForegroundColor Red
Write-Host "Script can't continue..." -ForegroundColor Red
Write-Host
break

}

####################################################

$JSON_Data = gc "$ImportPath"

# Excluding entries that are not required - id,createdDateTime,lastModifiedDateTime,version
$JSON_Convert = $JSON_Data | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty id,createdDateTime,lastModifiedDateTime,version,supportsScopeTags

$DisplayName = $JSON_Convert.displayName

$JSON_Output = $JSON_Convert | ConvertTo-Json -Depth 5
            
write-host
write-host "Device Configuration Policy '$DisplayName' Found..." -ForegroundColor Yellow
write-host
$JSON_Output
write-host
Write-Host "Adding Device Configuration Policy '$DisplayName'" -ForegroundColor Yellow
Add-DeviceConfigurationPolicy -JSON $JSON_Output