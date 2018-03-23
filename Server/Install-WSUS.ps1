<#

WSUS Configure

PRogram to install and configure WSUS on the local machine.

TO generate the product exclude list run the following command:

Get-WSUSProduct | % Product  | select Type,ID,Title | Out-GridView -OutputMode Multiple -Title 'Select EXCLUDE ONLY' | Export-Clixml -path .\ProdExclude.xml

#>

[cmdletbinding()]
param(
    $Path,
    $ProductExclude = '.\PRodExclude.xml'
)

#region Install WSUS Service
import-module servermanager -erroraction SilentlyContinue

if ( get-windowsfeature -Name UpdateServices | ? InstallState -ne Installed ) {

    Write-Verbose "`t`tInstall WSUS"

    Install-WindowsFeature -Name UpdateServices -IncludeManagementTools
}

#endregion

#region PostInstall 

if ( -not $path ) {

    write-verbose "path not defined, finding the best match..."

    $path = get-disk | 
        ? BusType -notin 'NVME','USB' | 
        ? Number -ne 0 | 
        get-partition | 
        get-volume | 
        sort SizeRemaining | 
        select -last 1 | 
        %{ $_.DriveLetter + ':\WSUS' }

    if ( -not $path ) {
        throw "no sutiable Path found for WSUS"
    }

    write-verbose $Path
}


if ( -not ( test-path "$Path\WsusContent" ) ) {

    write-verbose "`t`tPost Install Action"
    new-item -itemtype directory -path $path -erroraction silentlycontinue | out-null

    & 'C:\Program Files\Update Services\Tools\WsusUtil.exe' PostInstall "CONTENT_DIR=$Path"

}

#endregion

#region Best Practices Check

Invoke-BpaModel -ModelId Microsoft/Windows/UpdateServices

#endregion

#region Initial Sync...

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

#region Select Products and Classifications

if ( test-path $ProductExclude ) {

    $prodExcludeID = Import-Clixml -path $ProductExclude | % Product | % ID

    Get-WSUSProduct | where { $_.Product.ID -notin $prodExcludeID } | Set-WsusProduct

}
else {

    write-verbose "use the default list"
    $ExcludeList ='(Windows XP|Vista|2000|2001|2002|2003|2004|2005|2007|2008|2010|Windows 8|Exchange|Forefront)'

    Get-WSUSProduct | where { $_.Product.Title -notmatch $ExcludeList } | Set-WsusProduct
    
}


#Configure the Classifications
Get-WsusClassification | Where-Object {
    $_.Classification.Title -notin ( 'Drivers','Driver Sets','Tools' ) 
} | Set-WsusClassification

#endregion 

#region Set Auto Approval Rule

# Blindly get the existing global WSUS Classification rules
$GlobalClass = Get-WsusClassification | % Classification

$CLassCollection = new-object Microsoft.UpdateServices.Administration.UpdateClassificationCollection
$CLassCollection.AddRange($GlobalClass) 

# Get the first rule (will be the default)
get-wsusserver | 
    %{ $_.GetInstallApprovalRules() } | 
    Select-Object -first 1 |
    foreach-object {
        $_.SetUpdateClassifications($CLassCollection)
        $_.enabled = $true
        $_.Save()
        $_.ApplyRule()
        #$_.Enabled = $true
    }

#endregion

#region Kick off a Synchronization
 
#Configure Synchronizations
$subscription.SynchronizeAutomatically=$true
#Set synchronization scheduled for midnight each night
$subscription.SynchronizeAutomaticallyTimeOfDay= (New-TimeSpan -Hours 0)
$subscription.NumberOfSynchronizationsPerDay=1h

$subscription.Save()
 
#Kick off a synchronization
$subscription.StartSynchronization()

#endregion