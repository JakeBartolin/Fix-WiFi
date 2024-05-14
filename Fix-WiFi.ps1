# Fix--WiFi.ps1 was written by Jacob Bartolin © 2024
# Released under the GNU General Public License v2.0 (GPL-2.0)


# Checks if the script is running as admin or not.
# We're not using "# Require -RunasAdministrator" because it doesn't work if
# the script is copy / pasted into the terminal window.
function Test-AdminRights {
    $CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $SecPrincipal = New-Object System.Security.Principal.WindowsPrincipal($CurrentUser)
    return $SecPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-AdminRights)) {
    Write-Host "Please run this script as an administrator."
    exit
}


function connect-WiFi() {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SSID,
        [string]$WiFiPassword
        # We're going to close the session after execution, so plaintext isn't a massive problem.
    )
    $profilefile="ACprofile.xml"

    $SSIDHEX=($SSID.ToCharArray() |foreach-object {'{0:X}' -f ([int]$_)}) -join''
    $xmlfile="<?xml version=""1.0""?>
    <WLANProfile xmlns=""http://www.microsoft.com/networking/WLAN/profile/v1"">
        <name>$SSID</name>
        <SSIDConfig>
            <SSID>
                <hex>$SSIDHEX</hex>
                <name>$SSID</name>
            </SSID>
        </SSIDConfig>
        <connectionType>ESS</connectionType>
        <connectionMode>auto</connectionMode>
        <MSM>
            <security>
                <authEncryption>
                    <authentication>WPA2PSK</authentication>
                    <encryption>AES</encryption>
                    <useOneX>false</useOneX>
                </authEncryption>
                <sharedKey>
                    <keyType>passPhrase</keyType>
                    <protected>false</protected>
                    <keyMaterial>$WiFiPassword</keyMaterial>
                </sharedKey>
            </security>
        </MSM>
    </WLANProfile>
    "
    $WiFiPassword = $null # Cleanup the var, we're not complete monsters here.
    $XMLFILE > ($profilefile)
    netsh wlan add profile filename="$($profilefile)"
    netsh wlan connect name=$SSID
}

$WelcomeMessage=@"
___       __   ___                 ________ ___     
|\  \     |\  \|\  \               |\  _____\\  \    
\ \  \    \ \  \ \  \  ____________\ \  \__/\ \  \   
 \ \  \  __\ \  \ \  \|\____________\ \   __\\ \  \  
  \ \  \|\__\_\  \ \  \|____________|\ \  \_| \ \  \ 
   \ \____________\ \__\              \ \__\   \ \__\
    \|____________|\|__|               \|__|    \|__|                                                     
 ________ ___     ___    ___ _______   ________      
|\  _____\\  \   |\  \  /  /|\  ___ \ |\   __  \     
\ \  \__/\ \  \  \ \  \/  / | \   __/|\ \  \|\  \    
 \ \   __\\ \  \  \ \    / / \ \  \_|/_\ \   _  _\   
  \ \  \_| \ \  \  /     \/   \ \  \_|\ \ \  \\  \|  
   \ \__\   \ \__\/  /\   \    \ \_______\ \__\\ _\  
    \|__|    \|__/__/ /\ __\    \|_______|\|__|\|__| 
                 |__|/ \|__|                         
"@

Clear-Host
Write-Host $WelcomeMessage

# Splitting the functions up into steps for the SD rep to answer.
# This prompts them to confirm each step so things aren't forgotten.
$disableRDC = Read-Host "Do you want to disable Remote Differential Compression (Y/N)? Enter 'A' to auto-run all options."
$disableRDC = $disableRDC.ToUpper()
if ($disableRDC -eq "A") {
    $flushDNS = "Y"
    $turnIPV6Off = "Y"
    $restartNetAdapter = "Y"
    $clearWiFiProfiles = "Y"
    $disableRDC = "Y"
}
else {
    $flushDNS = Read-Host "Do you want to flush the DNS cache (Y/N)?"
    $flushDNS = $flushDNS.ToUpper()
    $turnIPV6Off = Read-Host "Do you want to turn IPV6 off for the current Wi-Fi adapter (Y/N)?"
    $turnIPV6Off = $turnIPV6Off.ToUpper()
    $restartNetAdapter = Read-Host "Do you want to restart the current Wi-Fi network adapter (Y/N)?"
    $restartNetAdapter = $restartNetAdapter.ToUpper()

    # ---iHeart version only clears two profiles---
    # $clearWiFiProfiles = Read-Host "Do you want to clear all exsisting Wi-Fi profiles (Y/N)?"
    $clearWiFiProfiles = Read-Host "Do you want to clear iHeart and iHeartGuest Wi-Fi profiles (Y/N)?"
    $clearWiFiProfiles = $clearWiFiProfiles.ToUpper()
}

Write-Host "Wi-Fi fixer will attempt to automatically reconnect to a Wi-Fi network once the script is complete."
$WiFiCredentials.SSID = Read-Host "What is the SSID of the Wi-Fi network (case-sensitive)?"
# Todo: check if this network name is good before proceeding.
$WiFiCredentials.password = Read-Host "What is the password of the Wi-Fi network (case sensitive)?"

Write-Host "--------------------"

# Disable RDC if possible
if ($disableRDC -eq "Y") {
    try {
        Write-Host "Checking if Remote Differential Compression (RDC) is off.`nIf not, turning it off."
        if ((Get-WindowsOptionalFeature -Online -FeatureName MSRDC-Infrastructure).State = "Disabled") {
            Write-Host "RDC was already disabled."
        }
        else {
            Write-Host "RDC is enabled, disabling..."
            Disable-WindowsOptionalFeature -Online -FeatureName MSRDC-Infrastructure
            Write-Host "RDC disabled."
        }
    }
    catch {
        Write-Error "Failed to turn off RDC. Error returned:`n`n" + $Error
    }
}
else {Write-Host "Disable RDC skipped."}

Write-Host "--------------------"

# Flush DNS if possible
if ($flushDNS -eq "Y") {
    try {
        Write-Host "Using 'ipconfig' to flush DNS..."
        cmd.exe /c "ipconfig /flushdns"
        Write-Host "DNS flushed."
    }
    catch {
        Write-Error "Failed to flush DNS. Error returned:`n`n" + $Error
    }
}
else {Write-Host "Flush DNS skipped."}

Write-Host "--------------------"

# Ensure IPV6 is off
if ($turnIPV6Off -eq "Y") {
    try {
        $IPV6Status = Get-NetAdapterBinding -name "Wi-Fi" -ComponentID ms_tcpip6
        if ($IPV6Status.Enabled) {
            Write-Host "IPV6 is turned on, turning off..."
            Disable-NetAdapterBinding -Name "Wi-Fi" -ComponentID ms_tcpip6
            Write-Host "IPV6 disabled for 'Wi-Fi'."
        }
        else {
            Write-Host "IPV6 for 'Wi-Fi'was already turned off."
        }
    }
    catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
        Write-Warning "Unable to find 'Wi-Fi' neetwork adapter.`nTrying 'WLAN' instead."
        $IPV6Status = Get-NetAdapterBinding -name "WLAN" -ComponentID ms_tcpip6
        if ($IPV6Status.Enabled) {
            Disable-NetAdapterBinding -Name "WLAN" -ComponentID ms_tcpip6
            Write-Host "IPV6 disabled for 'WLAN'."
        }
        else {
            Write-Host "IPV6 for 'WLAN' was already turned off."
        }
    }
    catch {
        Write-Error "Unable to turn off IPV6 for the current Wi-Fi adapter. Try doing it manually through the GUI.`nError returned:`n`n" + $Error
    }
}
else {Write-Host "Turn IPV6 off skipped"}

Write-Host "--------------------"

# Clear iHeart Wi-Fi profiles
if ($clearWiFiProfiles -eq "Y") {
    try {
        Write-Host "Using 'netsh' to remove all Wi-Fi profiles..."
        cmd.exe /c "netsh wlan delete profile name=* i=*"
        Write-Host "Wi-Fi profiles cleared."
    }
    catch {
        Write-Error "Something went wrong. Error returned: " + $Error
        Write-Warning "Attempting to reconnect to Wi-Fi network..."
        try {
            connect-WiFi -SSID $WiFiCredentials.SSID -WiFiPassword $WiFiCredentials.password
        }
        catch {
            Write-Error "Unable to reconnect to Wi-Fi. Please reconnect manually."
        }
    }
}
else {Write-Host "Clear Wi-Fi profiles skipped."}

Write-Host "--------------------"

# Restart the Wi-Fi network adapter.
if ($restartNetAdapter -eq "Y") {
    try {
        Write-Host "Restarting the Wi-Fi adapter. Your internet may cut out."
        Restart-NetAdapter -name "Wi-Fi"
        Write-Host "Wi-Fi adapter restarted."
    }
    catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
        Write-Warning "Unable to find NetAdapter 'Wi-Fi', trying 'WLAN'."
        Restart-NetAdapter -name "WLAN"
        Write-Host "Wi-Fi adapter (WLAN) restarted."
    }
    catch {
        Write-Error "Unable to restart the Wi-Fi adapter. Error Given:`n`n" + $Error
        Write-Warning "Attempting to reconnect to Wi-Fi network..."
        try {
            connect-WiFi
        }
        catch {
            Write-Error "Failed to reconnect to Wi-Fi."
        }
    }
}
else {Write-Host "Restart network adapter skipped."}

Write-Host "--------------------"

# Todo: check if we're already connected to this network (in case clearing profiles failed).
connect-WiFi -SSID $WiFiCredentials.SSID -WiFiPassword $WiFiCredentials.password
Write-Host "Reconnected to Wi-Fi network, please wait while the service representative reconnects."
