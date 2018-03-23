<#

Continue installation of SCCM using Microsoft 365 kit

#>

[cmdletbinding()]
param(
    [string] $SiteCode,
    [string] $Version = '1710'
    )

#region SCCM ConfigMgr Library

Import-Module "$($env:SMS_ADMIN_UI_PATH)\..\COnfigurationManager.psd1"

if ( -not $siteCode ) {
    $SiteCode = Get-PSDrive -PSProvider CMSite | Select-Object -First 1 | % Name
}

Set-Location "$($SiteCode)`:"

#endregion

#region Update SCCM to latest 

# Get embedded property list for SMS_WSUS_CONFIGURATION_MANAGER
$WMIComponent = Get-CimInstance -Namespace "root\SMS\site_$($SiteCode)" -ClassName SMS_SCI_Component -filter 'ItemName = "SMS_DMP_DOWNLOADER|SMS Dump Connetctor"' 
$WMIComponent.Props  = $WSUSComponent.Props | Where-Object PropertyName -eq SyncNow
$WMIComponent.Put()

################

Invoke-WebRequest https://raw.githubusercontent.com/NickolajA/PowerShell/master/ConfigMgr/Installation/Invoke-CMUpdatePackage.ps1 -OutFile $env:temp\Invoke-CMUpdatePackage.ps1

& $env:temp\Invoke-CMUpdatePackage.ps1 -version 1710 -SiteServer CM1 -verbose

#endregion 

#region Initial WSUS Sync...

#Get WSUS Server Object
$wsus = Get-WSUSServer
#Connect to WSUS server configuration
$wsusConfig = $wsus.GetConfiguration()
 
#Set to download updates from Microsoft Updates
Set-WsusServerSynchronization –SyncFromMU
 
#Set Update Languages to English and save configuration settings
$wsusConfig.AllUpdateLanguagesEnabled = $false           
$wsusConfig.SetEnabledUpdateLanguages("en")           
$wsusConfig.Save()
 
#Get WSUS Subscription and perform initial synchronization to get latest categories
$subscription = $wsus.GetSubscription()
$subscription.StartSynchronizationForCategoryOnly()
 
While ($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {
    $subscription.GetSynchronizationProgress() | %{ Write-Progress -Activity "$($_.Phase):  [ $($_.ProcessedItems) / $($_.TotalItems) ]" -PercentComplete ( 100 * $_.ProcessedItems / $_.TotalItems ) }
    Start-Sleep -Seconds 5
}

write-Progress -activity "Write" -Completed

#endregion

#region Select correct Products for subscription

Function Set-SUPProductSubscription {
    Param(
        [Parameter(Mandatory=$false)][String[]]$ProductName,
        [Parameter(Mandatory=$True)][Bool]$SubscriptionStatus,
        [Parameter(Mandatory=$False)][String]$CategoryTypeName,
        [Parameter(Mandatory=$False)][String[]]$CategoryInstance_UniqueID,
        [Parameter(Mandatory=$true)][String] $NameSpace
        )

    if(!($CategoryInstance_UniqueID)){
        Foreach ($Product in $ProductName){
            
                    if ($CategoryTypeName){
                        $Filter = "LocalizedCategoryInstanceName='$Product' AND CategoryTypeName='$CategoryTypeName'"
                    }else{
                        $Filter = "LocalizedCategoryInstanceName='$Product'"
                    }#End else

                    $CurrentInstance = Get-WmiObject -Namespace $namespace -Class SMS_UpdateCategoryInstance -Filter $Filter
                #Case for Windows Live which is present twice
                write-verbose "Attempting to set $($CurrentInstance.LocalizedCategoryInstanceName) Set to $SubscriptionStatus"
                $CurrentInstance.IsSubscribed = $SubscriptionStatus
                $CurrentInstance.Put() | Out-null
                #start-sleep 2
                Write-verbose "Subscription for Product $($CurrentInstance.LocalizedCategoryInstanceName) Set to $($CurrentInstance.IsSubscribed)"
                
                
        }
    }
    Else{
        foreach ($UniqueID in $CategoryInstance_UniqueID){
                $Filter = "CategoryInstance_UniqueID='$UniqueID'"

                $CurrentInstance = Get-WmiObject -Namespace $namespace -Class SMS_UpdateCategoryInstance -Filter $Filter
                #Case for Windows Live which is present twice...
                write-verbose "Attempting to set $($CurrentInstance.LocalizedCategoryInstanceName) Set to $SubscriptionStatus"
                $CurrentInstance.IsSubscribed = $SubscriptionStatus
                $CurrentInstance.Put() | Out-null
                #start-sleep 2
                Write-verbose "Subscription for Product $($CurrentInstance.LocalizedCategoryInstanceName) with UniqueID $($CurrentInstance.CategoryInstance_UniqueID) Set to $($CurrentInstance.IsSubscribed)"
        }
                
    }
           
}

$UpdateList = @(
    'Windows Defender'
    'Windows 10'
    'Windows 10 Fall Creators Update and Later Servicing Drivers'
    'Windows 10 Fall Creators Update and Later Upgrade & Servicing Drivers'
    'Windows 10 and later drivers'
    'Windows 10 and later upgrade & Servicing Drivers'
)

Set-SUPProductSubscription -NameSpace "root\SMS\site_$($SiteCode)" -SubscriptionStatus $True -ProductName $UpdateList

#endregion

#region Full WSUS Sync

# Configure the servicing plan



#endregion