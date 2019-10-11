$I = "[info]`t`t"; $E = "[error]`t`t"; $S = "[success]`t";
$PSVer = $PSVersionTable.PSVersion.Major

if ($PSVer -le 2) {
    Write-Host "$($E)PowerShell Version is too Old"
    Exit
}
$Dir = "C:\STS"
$ExtOld = "CryptoBlockerExtensions.old.txt"
$ExtNew = "CryptoBlockerExtensions.txt"
$URL = "https://fsrm.experiant.ca/api/v1/get"

$ExtGroupName = "CryptoBlocker_Extensions"
$TemplateName = "CryptoBlocker_Template"
$FileScreenName = "CryptoBlocker"

$KillSwitch = New-FsrmAction -Type Command -Command "c:\Windows\System32\cmd.exe" -CommandParameters "/c net stop lanmanserver /y" -SecurityLevel LocalSystem -KillTimeOut 0

Invoke-WebRequest $URL -OutFile "$($Dir)\$($ExtNew)" -UseBasicParsing

if (Test-Path "$($Dir)\$($ExtOld)") {
    Write-Host "$($I)Found Previous Extension List, Comparing if Any Changes Required"
    $Diff = Compare-Object -ReferenceObject $(Get-Content "$($Dir)\$($ExtNew)") -DifferenceObject $(Get-Content "$($Dir)\$($ExtOld)")
    if (!$Diff) {
        Write-Host "$($I)No New Extentions to Apply - Exiting"
        Exit
    }
}
else {
    Write-Host "$($I)Previous Extension List Missing"
    Write-Host "$($I)Either 1st Time Run or Deleted"
}

$Shares = Get-WmiObject Win32_Share | Select-Object Name,Path,Type | Where-Object { $_.Type -match  '0|2147483648' } | Select-Object -ExpandProperty Path | Select-Object -Unique

function ConvertFrom-Json20([Object] $obj) {
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    return ,$serializer.DeserializeObject($obj)
}

$jsonStr = Invoke-WebRequest -Uri $URL -UseBasicParsing
$Extensions = @(ConvertFrom-Json20($jsonStr) | ForEach-Object { $_.filters })

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
New-FsrmFileScreenTemplate -Name "$($TemplateName)" -Active:$True -IncludeGroup "$($ExtGroupName)"
ForEach ($Share in $Shares) {
    New-FsrmFileScreen -Path $Share -Active:$true -Description "$($FileScreenName)" -IncludeGroup "$($ExtGroupName)" -Template "$($TemplateName)"
    Write-Host "$($I)Share File Screen $($Share) based on $($TemplateName) for the Extensions List Group $($ExtGroupName) Has Been Created"
}
if (Test-Path -Path "$($Dir)\$($ExtOld)") {
    Remove-Item -Path "$($Dir)\$($ExtOld)"
}
if (Test-Path -Path "$($Dir)\$($ExtNew)") {
    Rename-Item -Path "$($Dir)\$($ExtNew)" -NewName "$($ExtOld)"
}