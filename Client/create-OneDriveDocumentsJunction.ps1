<#

Setup Folder redirection for Documents to OneDrive\Documents

#>

[cmdletbinding()]
param ( [switch] $force )


if ( (split-path ([environment]::GetFolderPath('MyDocuments'))).trim('\') -eq $env:onedrive.trim('\') ) {

    write-verbose "Documents Directory is stored on OneDrive"

    if ( get-item $env:USERPROFILE\Documents | ? LinkType -ne Junction ) {
        if ( get-childitem -path $env:USERPROFILE\Documents -file -Recurse ) {
            write-verbose "There is already a $env:UserProfile\Documents directory"
            if ( -not $force ) {
                throw "Files present on Documents: $env:UserProfile\Documents\*"
            }
        }
        cmd.exe /c rd /s /q "$env:USERPROFILE\Documents"
    }

    if ( -not ( get-item $env:USERPROFILE\Documents ) ) {
        Write-verbose "No folder exists, continue..."
        cmd.exe /c mklink /J "$env:USERPROFILE\Documents" ([environment]::GetFolderPath('MyDocuments'))
    }

    write-verbose "done"
}
