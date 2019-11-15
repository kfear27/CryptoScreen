# CryptoScreen

CryptoScreen uses Microsoft's FileScreens to block extensions known to be used by Ransomware/Crypto viruses.

This tool was created to work on Server 2008 (6.0) through to 2019+ (10).

On older systems it will use the `filescrn.exe` executable and on newer it will use the PowerShell cmdlets.

The default working directory is set to `C:\STS`, change the `$Dir` variable value if you wish to change this.

Exclusions can be added per extension or share via files in your working $Dir:
* CryptoScreen_ExcludedShares.txt
* CryptoScreen_ExcludedExtensions.txt

Add one Share or Extension per line in these files, or simply add them to the variable in the script in this format:

* `$ExcludedShares = @('C:\Share1','D:\DATA\Shares82')`
* `$ExcludedExtensions = @('*.ext3','*.crypto')`

Use both if you wish, it will merge them if the file exists and there is data already passed in the array within the script.

By default violations will be logged within Event Viewer, there is a 'Kill Switch' configured with the `$KillSwitch` variable in which you can add this after the `-Notification` PowerShell switch.

### PowerShell Kill Switch Example

```powershell
$KillSwitch = New-FsrmAction -Type Command -Command "c:\Windows\System32\cmd.exe" -CommandParameters "/c net stop lanmanserver /y" -SecurityLevel LocalSystem -KillTimeOut 0
$EventLogMsg = "The user [Source Io Owner] try to save [Source File Path] in [File Screen Path] on [Server]. This extension is contained in [Violated File Group], and is not permit on this server."
$TemplateName = "CryptoScreen_Template"
$ExtGroupName = "CryptoScreen_Extensions"
$Notification = New-FsrmAction -Type Event -EventType Warning -Body $($EventLogMsg) -RunLimitInterval 60
New-FsrmFileScreenTemplate -Name "$($TemplateName)" -Active:$True -IncludeGroup "$($ExtGroupName)" -Notification $Notification,$KillSwitch
```

### Thanks

A huge Kudos to @nexxai and @daviddande and their projects below who had a huge part in creating CryptoScreen

* https://github.com/nexxai/CryptoBlocker
* https://github.com/davidande/FSRM-ANTICRYPTO
