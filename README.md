# CryptoScreen

CryptoScreen uses Microsoft's FileScreens to block extensions known to be used by Ransomware/Crypto viruses.

This tool was created to work on Server 2008 (6.0) through to 2019+ (10).

On older systems it will use the `filescrn.exe` executable and on newer it will use the PowerShell cmdlets.

The default working directory is set to `C:\STS`, change the `$Dir` value if you wish to change this.

Exclusions can be added per extension or share via files in your working $Dir:
* CryptoScreen_ExcludedShares.txt
* CryptoScreen_ExcludedExtensions.txt

Add one Share or Extension per line in these files, or simply add them to the variable in the script in this format:

* `$ExcludedShares = @('C:\Share1','D:\DATA\Shares82')`
* `$ExcludedExtensions = @('*.ext3','*.crypto')`

Use both if you wish, it will merge them if the file exists and there is data already passed in the array within the script.

### Thanks

A huge Kudos to @nexxai and @daviddande and their projects below who had a huge part in creating CryptoScreen

* https://github.com/nexxai/CryptoBlocker
* https://github.com/davidande/FSRM-ANTICRYPTO
