$I = "[info]`t`t"; $E = "[error]`t`t"; $S = "[success]`t";
$ErrorActionPreference = "SilentlyContinue"

## Working Directory of the Script
$Dir = "C:\STS"
## File Names of Bad Extensions, Old & New used for Comparision
$ExtNew = "CryptoScreenExtensions.txt"
$ExtOld = "CryptoScreenExtensions.old.txt"
## URL With Known Bad Extensions
$URL = "https://fsrm.experiant.ca/api/v1/get"
## Naming Scheme for Screens, Templates & Extensions
$FileScreenName = "CryptoScreen"
$TemplateName = "CryptoScreen_Template"
$ExtGroupName = "CryptoScreen_Extensions"
## Exclusion Arrays for Extensions & Shares
## @('add*','*.exclusions','in*this*','format.csv')
$ExcludedShares = @();
$ExcludedExtensions = @();
## You can use a txt file for each exclusion list if you prefer
## Add one exclusion per line and save the file(s) in the same folder as $Dir
$ExcludedSharesFile = "CryptoScreen_ExcludedShares.txt"
$ExcludedExtensionsFile = "CryptoScreen_ExcludedExtensions.txt"

## Event Log Message
$EventLogMsg = "The user [Source Io Owner] try to save [Source File Path] in [File Screen Path] on [Server]. This extension is contained in [Violated File Group], and is not permit on this server."

if (Test-Path "$($Dir)\$($ExcludedSharesFile)") {
    $ExcludedSharesFileContents = Get-Content "$($Dir)\$($ExcludedSharesFile)" | ForEach-Object { $_.trim() }
    ForEach ($ExShare in $ExcludedSharesFileContents) {
        $ExcludedShares += $ExShare
    }
}
if (Test-Path "$($Dir)\$($ExcludedExtensionsFile)") {
    $ExcludedExtensionsFileContents = Get-Content "$($Dir)\$($ExcludedExtensionsFile)" | ForEach-Object { $_.trim() }
    ForEach ($ExExt in $ExcludedExtensionsFileContents) {
        $ExcludedExtensions += $ExExt
    }
}

Invoke-WebRequest $URL -OutFile "$($Dir)\$($ExtNew)" -UseBasicParsing

if (Test-Path "$($Dir)\$($ExtOld)") {
    Write-Host "$($I)Found Previous Extension List, Comparing if Any Changes Required"
    $Diff = Compare-Object -ReferenceObject $(Get-Content "$($Dir)\$($ExtNew)") -DifferenceObject $(Get-Content "$($Dir)\$($ExtOld)")
    if (!$Diff) {
        Write-Host "$($I)No New Extentions to Apply - Exiting"
        Remove-Item -Path "$($Dir)\$($ExtNew)"
        Exit
    }
} else { Write-Host "$($I)Previous Extension List Missing"; Write-Host "$($I)Either 1st Time Run or Deleted" }

$PSVer = $PSVersionTable.PSVersion.Major
$majorVer = [System.Environment]::OSVersion.Version.Major
$minorVer = [System.Environment]::OSVersion.Version.Minor
$OS = "Unknown";
if ($PSVer -le 2) {
    Write-Host "$($E)PowerShell Version Out of Date"
    Exit
}
if ($majorVer -ge 6) {
    if ($majorVer -eq 10) { $OS = "2016+" }
    if ($majorVer -eq 6) {
        if ($minorVer -eq 3) { $OS = "2012R2" }
        if ($minorVer -eq 2) { $OS = "2012" }
        if ($minorVer -eq 1) { $OS = "2008R2" }
        if ($minorVer -eq 0) { $OS = "2008" }
    }
} else { Write-Host "$($E)Unknown OS, Exiting"; exit; }
Import-Module ServerManager
$checkFSRM = Get-WindowsFeature -Name FS-Resource-Manager
if (($OS -eq "2016+") -or ($OS -eq "2012R2") -or ($OS -eq "2012")) {
    if ($checkFSRM.Installed -ne "True") {
        Write-Host "$($I)Server 2012 or Higher Detected, Checking for FSRM"
        $Install = Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools
        if ($? -ne $True) { Write-Host "$($E)Install of FSRM Failed, Exiting"; exit; }
    }
    $Method = "PowerShell";
}
if ($OS -eq "2008R2") {
    if ($checkFSRM.Installed -ne "True") {
        Write-Host "$($I)Server 2008R2 Detected, Checking for FSRM"
        $Install = Add-WindowsFeature FS-FileServer, FS-Resource-Manager
        if ($? -ne $True) { Write-Host "$($E)Install of FSRM Failed, Exiting"; exit; }
        $Method = "&filescrn.exe";
    }
}
if ($OS -eq "2008") {
    if ($checkFSRM.Installed -ne "True") {
        Write-Host "$($I)Server 2008 Detected, Checking for FSRM"
        $Install = &servermanagercmd -Install FS-FileServer FS-Resource-Manager
        if ($Install -like "*already installed*") { Write-Host "$($I)FSRM Already Installed" }
        else { Write-Host "$($E)Please Manually Install FSRM"; exit; }
    }
}

$Shares = Get-WmiObject Win32_Share | Select-Object Name,Path,Type | Where-Object { $_.Type -match  '0|2147483648' } | Select-Object -ExpandProperty Path | Select-Object -Unique

Function ConvertFrom-Json20([Object] $obj) {
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    return ,$serializer.DeserializeObject($obj)
}

Function Split-ExtensionGroup {
    param(
        $Ext
    )
    $Ext = $Ext | Sort-Object -Unique
    $workingArray = @()
    $WorkingArrayIndex = 1
    $LengthOfStringsInWorkingArray = 0
    $Ext | ForEach-Object {
        if (($LengthOfStringsInWorkingArray + 1 + $_.Length) -gt 4000) {
            [PSCustomObject]@{
                index = $WorkingArrayIndex
                ExtGroupName = "$Script:ExtGroupName$WorkingArrayIndex"
                array = $workingArray
            }
            $workingArray = @($_)
            $LengthOfStringsInWorkingArray = $_.Length
            $WorkingArrayIndex++
        }
        else {
            $workingArray += $_
            $LengthOfStringsInWorkingArray += (1 + $_.Length)
        }
    }
    [PSCustomObject]@{
        index = ($WorkingArrayIndex)
        ExtGroupName = "$Script:ExtGroupName$WorkingArrayIndex"
        array = $workingArray
    }
}

$jsonStr = Invoke-WebRequest -Uri $URL -UseBasicParsing
$tempExt = @(ConvertFrom-Json20($jsonStr) | ForEach-Object { $_.filters })
$Extensions = @();
ForEach ($Ext in $tempExt) {
    if ($Ext -notin $ExcludedExtensions) { $Extensions += $Ext }
}

if (($OS -ne "2016+") -or ($OS -ne "2012R2") -or ($OS -ne "2012")) {
    $ExtensionGroups = @(Split-ExtensionGroup $Extensions)
}

if ($Method -eq "PowerShell") {

    ## Example of a Kill Switch, this is not used in production
    ## This Kill Switch stops the Shares
    ## This can be added after the -Notification switch, -Notification $Notification,$KillSwitch
    $KillSwitch = New-FsrmAction -Type Command -Command "c:\Windows\System32\cmd.exe" -CommandParameters "/c net stop lanmanserver /y" -SecurityLevel LocalSystem -KillTimeOut 0

    $delFSRMShares = Get-FsrmFileScreen | Select-Object Template, Path | Where-Object { $_.Template -like "$($TemplateName)" } | Select-Object -ExpandProperty Path
    ForEach ($Path in $delFSRMShares) {
        Remove-FsrmFileScreen $Path -Confirm:$False
        Write-Host "$($I)FSRM Share $($Path) using File Screen Template $($TemplateName) Deleted"
    }
    $delScreentemplate = Get-FsrmFileScreenTemplate | Select-Object Name | Where-Object { $_.Name -like "$($TemplateName)" } | Select-Object -ExpandProperty Name
    ForEach ($Name in $delScreenTemplate) {
        Remove-FsrmFileScreenTemplate $Name -Confirm:$False
        Write-Host "$($I)FSRM Screen Template $($Name) using File Group Name $ExtGroupName Deleted"
    }
    $delFSRMGroupName = Get-FsrmFileGroup | Select-Object Name | Where-Object { $_.Name -like "$($ExtGroupName)" } | Select-Object -ExpandProperty Name
    ForEach ($Name in $delFSRMGroupName) {
        Remove-FsrmFileGroup $Name -Confirm:$False
        Write-Host "$($I)FSRM File Group $($Name) Deleted"
    }
    Write-Host "$($I)Creating FSRM File Group $($ExtGroupName)"
    New-FsrmFileGroup -Name "$($ExtGroupName)" -IncludePattern $Extensions

    Write-Host "$($I)Creating FSRM File Template $($TemplateName) including $($TemplateName)"
    $Notification = New-FsrmAction -Type Event -EventType Warning -Body $($EventLogMsg) -RunLimitInterval 60
    New-FsrmFileScreenTemplate -Name "$($TemplateName)" -Active:$True -IncludeGroup "$($ExtGroupName)" -Notification $Notification
    ForEach ($Share in $Shares) {
        if ($Share -notin $ExcludedShares) {
            New-FsrmFileScreen -Path $Share -Active:$true -Description "$($FileScreenName)" -IncludeGroup "$($ExtGroupName)" -Template "$($TemplateName)"
            Write-Host "$($I)Share File Screen $($Share) based on $($TemplateName) for the Extensions List Group $($ExtGroupName) Has Been Created"
        } else { Write-Host "$($I)Share of $($Share) Has Been Excluded" -ForegroundColor Green }
    }
}
else {
    ForEach ($group in $ExtensionGroups) {
        &filescrn.exe Filegroup Delete "/Filegroup:$($group.ExtGroupName)" /Quiet
        &filescrn.exe Filegroup Add "/Filegroup:$($group.ExtGroupName)" "/Members:$($group.array -Join '|')"
    }
    &filescrn.exe Template Delete /Template:$TemplateName /Quiet
    $Arguments = 'Template', 'Add', "/Template:$TemplateName", "/Type:Active", "/Add-Notification:e,$EventLogMsg"
    ForEach ($group in $ExtensionGroups) {
        $Arguments += "/Add-Filegroup:$($group.ExtGroupName)"
    }
    &filescrn.exe $Arguments
    ForEach ($Share in $Shares) {
        if ($Share -notin $ExcludedShares) {
            &filescrn.exe Screen Delete "/Path:$Share" /Quiet
            &filescrn.exe Screen Add "/Path:$Share" "/SourceTemplate:$TemplateName"
        } else { Write-Host "$($I)Share of $($Share) Has Been Excluded" -ForegroundColor Green }
    }
}

if (Test-Path -Path "$($Dir)\$($ExtOld)") {
    Remove-Item -Path "$($Dir)\$($ExtOld)"
}
if (Test-Path -Path "$($Dir)\$($ExtNew)") {
    Rename-Item -Path "$($Dir)\$($ExtNew)" -NewName "$($ExtOld)"
}
