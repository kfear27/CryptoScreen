# CryptoScreen

CryptoScreen uses Microsoft's FileScreens to block extensions known to be used by Ransomware/Crypto viruses.

This tool was created to work on Server 2008 (6.0) through to 2019+ (10).

On older systems it will use the `filescrn.exe` executable and on newer it will use the PowerShell cmdlets.

The default working directory is set to `C:\STS`, change the `$Dir` variable value if you wish to change this.

Exclusions can be added into the textarea variable `$CryptoScreenExclusions` or in the `ExclusionsFile` file.
Default FileName: CryptoScreen_Exclusions.txt

You can exclude Shares and Extensions, one per line ie.
```
*.extension
G:\Excluded_Share\Name\Here With\Spaces
```
You can place exclusions in both the script and the local file on the machine, it will emrge the two.

By default violations will be logged within Event Viewer, there is a 'Kill Switch' configured with the `$KillSwitch` variable in which you can add this after the `-Notification` PowerShell switch.

### PowerShell Kill Switch Example

```powershell
$KillSwitch = New-FsrmAction -Type Command -Command "c:\Windows\System32\cmd.exe" -CommandParameters "/c net stop lanmanserver /y" -SecurityLevel LocalSystem -KillTimeOut 0
$EventLogMsg = "[Source Io Owner] attempted to save [Source File Path] in [File Screen Path] on [Server]. This extension is contained in [Violated File Group], and is not permit on this server."
$TemplateName = "CryptoScreen_Template"
$ExtGroupName = "CryptoScreen_Extensions"
$Notification = New-FsrmAction -Type Event -EventType Warning -Body $($EventLogMsg) -RunLimitInterval 60
New-FsrmFileScreenTemplate -Name "$($TemplateName)" -Active:$True -IncludeGroup "$($ExtGroupName)" -Notification $Notification,$KillSwitch
```

### Thanks

A huge Kudos to @nexxai and @daviddande and their projects below who had a huge part in creating CryptoScreen

* https://github.com/nexxai/CryptoBlocker
* https://github.com/davidande/FSRM-ANTICRYPTO
