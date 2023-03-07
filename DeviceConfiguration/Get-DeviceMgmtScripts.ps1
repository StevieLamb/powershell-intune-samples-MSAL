
<#

    Modified version of script found at
    https://github.com/microsoftgraph/powershell-intune-samples/blob/master/DeviceConfiguration/DeviceManagementScripts_Get.ps1

    .DESCRIPTION
    This version uses the MSAL via MSAL.PS, rather than ADAL which will be discontinued soon.
    It alsos therefore avoids the AzureAD/AzureADPreview modules

    Requires:
    MSAL.PS module (available from PSGalery)
    An App Registration in the M365 tenant's Azure AD, with the following:
    MS Graph API permission, type Application: DeviceManagementConfiguration.ReadWrite.All
    A certificate keypair: must be installed on machine running script, and its public key added to the app
    under Certificates and secrets

    .PARAMETER tenant
    The target tenant

    .PARAMETER AppId
    The AppID or clientID of the App Registration to use

    .PARAMETER certThumbprint
    The thumbprint of the certificate associated with the application
    This certificate must be installed in the user's Personal >> Certificates store on the
    computer running the script

    .EXAMPLE
    Get-DeviceMgmtScripts.ps1 -tenant contoso.com -AppId "0000-0000000-0000000-00000" -certThumbprint AHG4587JDHFNMMN587MNSJHJFMN48762MN
    Connects to the tenant by its default DNS domain using a pre-registered App Reg and certificate, then outputs the contents of all scripts to console, along with their assignments

#>

####################################################

[cmdletbinding()]
param (
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

Function Get-DeviceManagementScripts(){

<#
.SYNOPSIS
This function is used to get device management scripts from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any device management scripts
.EXAMPLE
Get-DeviceManagementScripts
Returns any device management scripts configured in Intune
Get-DeviceManagementScripts -ScriptId $ScriptId
Returns a device management script configured in Intune
.NOTES
NAME: Get-DeviceManagementScripts
#>

[cmdletbinding()]

param (

    [Parameter(Mandatory=$false)]
    $ScriptId

)

$graphApiVersion = "Beta"
$Resource = "deviceManagement/deviceManagementScripts"
    
    try {

        if($ScriptId){

        $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource/$ScriptId"

        Invoke-RestMethod -Uri $uri -Headers $AuthHeader -Method Get

        }

        else {

        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Resource)?`$expand=groupAssignments"
        (Invoke-RestMethod -Uri $uri -Headers $AuthHeader -Method Get).Value

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

Function Get-AADGroup(){
    
<#
.SYNOPSIS
This function is used to get AAD Groups from the Graph API REST interface
.DESCRIPTION
The function connects to the Graph API Interface and gets any Groups registered with AAD
.EXAMPLE
Get-AADGroup
Returns all users registered with Azure AD
.NOTES
NAME: Get-AADGroup
#>
    
[cmdletbinding()]
    
param
(
    $GroupName,
    $id,
    [switch]$Members
)
    
# Defining Variables
$graphApiVersion = "v1.0"
$Group_resource = "groups"
    
    try {
    
        if($id){
    
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=id eq '$id'"
        (Invoke-RestMethod -Uri $uri -Headers $AuthHeader -Method Get).Value
    
        }
    
        elseif($GroupName -eq "" -or $GroupName -eq $null){
    
        $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)"
        (Invoke-RestMethod -Uri $uri -Headers $AuthHeader -Method Get).Value
    
        }
    
        else {
    
            if(!$Members){
    
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=displayname eq '$GroupName'"
            (Invoke-RestMethod -Uri $uri -Headers $AuthHeader -Method Get).Value
    
            }
    
            elseif($Members){
    
            $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)?`$filter=displayname eq '$GroupName'"
            $Group = (Invoke-RestMethod -Uri $uri -Headers $AuthHeader -Method Get).Value
    
                if($Group){
    
                $GID = $Group.id
    
                $Group.displayName
                write-host
    
                $uri = "https://graph.microsoft.com/$graphApiVersion/$($Group_resource)/$GID/Members"
                (Invoke-RestMethod -Uri $uri -Headers $AuthHeader -Method Get).Value
    
                }
    
            }
    
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

#region Authentication

$AuthHeader = MSALAuth -tenantID $tenant -clientID $AppId -thumbprint $certThumbprint

#endregion

####################################################

$PSScripts = Get-DeviceManagementScripts

if($PSScripts){

    write-host "-------------------------------------------------------------------"
    Write-Host

    $PSScripts | foreach {

    $ScriptId = $_.id
    $DisplayName = $_.displayName

    Write-Host "PowerShell Script: $DisplayName..." -ForegroundColor Yellow

    $_

    write-host "Device Management Scripts - Assignments" -f Cyan

    $Assignments = $_.groupAssignments.targetGroupId
    
        if($Assignments){
    
            foreach($Group in $Assignments){
    
            (Get-AADGroup -id $Group).displayName
    
            }
    
            Write-Host
    
        }
    
        else {
    
        Write-Host "No assignments set for this policy..." -ForegroundColor Red
        Write-Host
    
        }

    $Script = Get-DeviceManagementScripts -ScriptId $ScriptId

    $ScriptContent = $Script.scriptContent

    Write-Host "Script Content:" -ForegroundColor Cyan

    [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String("$ScriptContent"))

    Write-Host
    write-host "-------------------------------------------------------------------"
    Write-Host

    }

}

else {

Write-Host
Write-Host "No PowerShell scripts have been added to the service..." -ForegroundColor Red
Write-Host

}
