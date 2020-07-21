# Working Directory of the Script
$Dir = "C:\STS"

# Exclusions File (Optional)
# Add one exclusion per line, either file extensions with or without wildcards and share locations like D:\Data\Share
$ExclusionsFile = "CryptoScreen_Exclusions.txt"

# Naming Scheme for Screens, Templates & Extensions
$FileScreenName = "CryptoScreen"
$TemplateName = "CryptoScreen_Template"
$ExtGroupName = "CryptoScreen_Extensions"

$CryptoScreenExtensions = Invoke-WebRequest -Uri "https://fsrm.experiant.ca/api/v1/get" -UseBasicParsing
$Extensions = ($CryptoScreenExtensions | ConvertFrom-Json).Filters

# Event Log Message
$EventLogMsg = "[Source Io Owner] attempted to save [Source File Path] in [File Screen Path] on [Server]. This extension is contained in [Violated File Group], and is not permit on this server."

$PowerShellVersion = $PSVersionTable.PSVersion.Major
if ($PowerShellVersion -le 2) { Write-Host "Update PowerShell before continuing. Current version is 2.0 or lower" -ForegroundColor Red; Exit; }

[decimal]$OSVersion = -Join ([System.Environment]::OSVersion.Version.Major,".",[System.Environment]::OSVersion.Version.Minor)
Write-Host "OS Version Number: $($OSVersion)"
if ($OSVersion -ge 6.2) { $UsePowerShellModule = $True } else { $UsePowerShellModule = $False }
if ($UsePowerShellModule) { Write-Host "Using PowerShell Commands for FSRM (OS >= 6.2)" } else { Write-Host "Using &filescrn.exe Executable Comamnds for FSRM (OS < 6.2)" }
Import-Module ServerManager | Out-Null
$FSRM = Get-WindowsFeature -Name FS-Resource-Manager
if ($FSRM.Installed -ne "True") {
    if ($OSVersion -ge 6.2) {
        $Install = Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools
        if ($? -ne $True) { Write-Host "Install of FSRM Failed, Exiting"; Exit; }
    }
    elseif ($OSVersion -eq 6.1) {
        $Install = Add-WindowsFeature FS-FileServer, FS-Resource-Manager
        if ($? -ne $True) { Write-Host "Install of FSRM Failed, Exiting"; Exit; }
    }
    elseif ($OSVersion -eq 6.0) {
        $Install = &servermanagercmd -Install FS-FileServer FS-Resource-Manager
        if ($Install -Like "*already installed*") { Write-Host "FSRM Already Installed" }
        else { Write-Host "Please Manually Install FSRM, Exiting..."; Exit; }
    }
}

$Shares = Get-WmiObject Win32_Share | Select-Object Name,Path,Type | Where-Object { $_.Type -match  '0|2147483648' } | Select-Object -ExpandProperty Path | Select-Object -Unique

$CryptoScreenExclusions = @"
*.add_some
C:\Exclusions_Here
using_one.per_line*
OR-pass-them-in
D:\Using\A\Script
"@
$Exclusions = @()
$Exclusions += $CryptoScreenExclusions.Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries)
if (Test-Path "$($Dir)\$($ExclusionsFile)") {
    $ExcludedFileContents = Get-Content "$($Dir)\$($ExclusionsFile)" | ForEach-Object { $_.trim() }
    ForEach ($Line in $ExcludedFileContents) {
        $Exclusions += $Line
    }
}
$ExcludedShares = @()
$ExcludedExtensions = @()

ForEach ($Exclusion in $Exclusions) {
    if (($Exclusion -Like "*\*") -Or ($Exclusion -Like "*:*")) {
        $ExcludedShares += $Exclusion
    }
    else {
        $ExcludedExtensions += $Exclusion
    }
}

Write-Host "Total Excluded Items: $($Exclusions.Count)"
Write-Host "Total Excluded Shares: $($ExcludedShares.Count)"
Write-Host "Total Excluded Extensions: $($ExcludedExtensions.Count)"

$RecompiledExtensions = @()
ForEach ($Extension in $Extensions) {
    if ($ExcludedExtensions -NotContains $Extension) {
        $RecompiledExtensions += $Extension
    }
    else { Write-Host "Extension Excluded: $($Extension)" }
}

Write-Host "Total Extensions from API: $($Extensions.Count)"
Write-Host "Total Extensions Without Exclusions: $($RecompiledExtensions.Count)"


if ($UsePowerShellModule) {
    # Example of a Kill Switch, this is not used in production
    # This Kill Switch stops the Shares
    # This can be added after the -Notification switch, -Notification $Notification,$KillSwitch
    $KillSwitch = New-FsrmAction -Type Command -Command "c:\Windows\System32\cmd.exe" -CommandParameters "/c net stop lanmanserver /y" -SecurityLevel LocalSystem -KillTimeOut 0

    $FSRMShares = Get-FsrmFileScreen | Select-Object Template, Path | Where-Object { $_.Template -like "$($TemplateName)" } | Select-Object -ExpandProperty Path
    ForEach ($Path in $FSRMShares) {
        Remove-FsrmFileScreen $Path -Confirm:$False
        Write-Host "FSRM Share $($Path) using File Screen Template $($TemplateName) Deleted"
    }
    $Screentemplate = Get-FsrmFileScreenTemplate | Select-Object Name | Where-Object { $_.Name -like "$($TemplateName)" } | Select-Object -ExpandProperty Name
    ForEach ($Name in $ScreenTemplate) {
        Remove-FsrmFileScreenTemplate $Name -Confirm:$False
        Write-Host "FSRM Template $($Name) using File Group Name $($ExtGroupName) Deleted"
    }
    $FSRMGroupName = Get-FsrmFileGroup | Select-Object Name | Where-Object { $_.Name -like "$($ExtGroupName)" } | Select-Object -ExpandProperty Name
    ForEach ($Name in $FSRMGroupName) {
        Remove-FsrmFileGroup $Name -Confirm:$False
        Write-Host "FSRM File Group $($Name) Deleted"
    }
    Write-Host "Creating FSRM File Group $($ExtGroupName)"
    New-FsrmFileGroup -Name "$($ExtGroupName)" -IncludePattern $RecompiledExtensions | Out-Null
    Write-Host "Creating FSRM File Template $($TemplateName) With Extension Group $($ExtGroupName)"
    $Notification = New-FsrmAction -Type Event -EventType Warning -Body $($EventLogMsg) -RunLimitInterval 60
    New-FsrmFileScreenTemplate -Name "$($TemplateName)" -Active:$True -IncludeGroup "$($ExtGroupName)" -Notification $Notification
    ForEach ($Share in $Shares) {
        if ($Share -NotIn $ExcludedShares) {
            New-FsrmFileScreen -Path $Share -Active:$True -Description "$($FileScreenName)" -IncludeGroup "$($ExtGroupName)" -Template "$($TemplateName)"
            Write-Host "Share File Screen $($Share) based on $($TemplateName) for the Extensions List Group $($ExtGroupName) Has Been Created"
        } else { Write-Host "Share $($Share) Has Been Excluded" -ForegroundColor Green }
    }
}
else {
    Function Split-ExtensionGroup {
        param($Ext)
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
    $ExtensionGroups = @(Split-ExtensionGroup $RecompiledExtensions)
    ForEach ($Group in $ExtensionGroups) {
        &filescrn.exe Filegroup Delete "/Filegroup:$($Group.ExtGroupName)" /Quiet
        &filescrn.exe Filegroup Add "/Filegroup:$($Group.ExtGroupName)" "/Members:$($Group.array -Join '|')"
    }
    &filescrn.exe Template Delete /Template:$TemplateName /Quiet
    $Arguments = 'Template', 'Add', "/Template:$TemplateName", "/Type:Active", "/Add-Notification:e,$EventLogMsg"
    ForEach ($Group in $ExtensionGroups) {
        $Arguments += "/Add-Filegroup:$($Group.ExtGroupName)"
    }
    &filescrn.exe $Arguments
    ForEach ($Share in $Shares) {
        if ($Share -NotIn $ExcludedShares) {
            &filescrn.exe Screen Delete "/Path:$Share" /Quiet
            &filescrn.exe Screen Add "/Path:$Share" "/SourceTemplate:$TemplateName"
        } else { Write-Host "Share $($Share) Has Been Excluded" -ForegroundColor Green }
    }
}

# Fin!
