<#

Setup Folder redirection for Desktop to OneDrive\Desktop

#>

[cmdletbinding()]
param ( [switch] $force )


if ( (split-path ([environment]::GetFolderPath('DesktopDirectory'))).trim('\') -eq $env:onedrive.trim('\') ) {

    write-verbose "Desktop Directory is stored on OneDrive"

    if ( get-item $env:USERPROFILE\Desktop | ? LinkType -ne Junction ) {
        if ( get-childitem -path $env:USERPROFILE\Desktop -file -Recurse ) {
            write-verbose "There is already a $env:UserProfile\Desktop directory"
            if ( -not $force ) {
                throw "Files present on Desktop: $env:UserProfile\Desktop\*"
            }
        }
        cmd.exe /c rd /s /q "$env:USERPROFILE\Desktop"
    }

    if ( -not ( get-item $env:USERPROFILE\Desktop ) ) {
        Write-verbose "No folder exists, continue..."
        cmd.exe /c mklink /J "$env:USERPROFILE\Desktop" ([environment]::GetFolderPath('DesktopDirectory'))
    }

    write-verbose "done"
}