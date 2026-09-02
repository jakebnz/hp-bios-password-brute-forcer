<#
.DESCRIPTION   
Downloads the current HP CMSL installer from HP's download page and installs it silently.
Verifies the HP BIOS password cmdlets are callable in Windows PowerShell 5.1.
Run from an elevated Windows PowerShell 5.1 prompt. It is safe to re-run.

.PARAMETER InstallPath
Working folder for the downloaded installer and the transcript log.

.PARAMETER SetExecutionPolicy
Sets LocalMachine execution policy to RemoteSigned. The HP modules are signed,
but a Restricted policy will still block importing them interactively.

.EXAMPLE
.\install.ps1 -SetExecutionPolicy
#>

[CmdletBinding()]
param(
    [string]$InstallPath = "$env:ProgramData\HPBiosBench",
    [switch]$SetExecutionPolicy
)

$ErrorActionPreference = 'Stop'

# --- Preflight ------------------------------------------------------------

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell prompt.'
}

if (-not (Test-Path $InstallPath)) {
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path (Join-Path $InstallPath "bench-setup_$(Get-Date -Format 'yyyyMMdd-HHmmss').log") | Out-Null

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Step { param($Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param($Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "    $Message" -ForegroundColor Yellow }

# --- 1. HP CMSL installer -------------------------------------------------

Write-Step 'Downloading HP CMSL from hp.com'

# Do not use ftp.hp.com/.../hp-cmsl-latest.exe. That URL has served a stale
# version (1.5.0) for years. Scrape the actual download page instead.
$downloadPage = 'https://www.hp.com/us-en/solutions/client-management-solutions/download.html'
$page = Invoke-WebRequest -Uri $downloadPage -UseBasicParsing

$cmslUrl = ($page.Links | Where-Object { $_.href -match 'hp-cmsl.*\.exe$' } |
            Select-Object -First 1).href

if (-not $cmslUrl) {
    throw "Could not find an hp-cmsl EXE link on $downloadPage. HP may have changed the page; download the installer manually."
}
if ($cmslUrl -notmatch '^https?://') {
    $cmslUrl = ([Uri]::new([Uri]$downloadPage, $cmslUrl)).AbsoluteUri
}

$installer = Join-Path $InstallPath ([IO.Path]::GetFileName($cmslUrl))
Write-Ok "Source: $cmslUrl"
Invoke-WebRequest -Uri $cmslUrl -OutFile $installer -UseBasicParsing
Write-Ok "Saved: $installer ($([math]::Round((Get-Item $installer).Length / 1MB, 1)) MB)"

Write-Step 'Verifying the installer signature'
$sig = Get-AuthenticodeSignature -FilePath $installer
if ($sig.Status -ne 'Valid') {
    throw "Signature check failed: $($sig.Status). Do not run this file."
}
if ($sig.SignerCertificate.Subject -notmatch 'HP Inc|Hewlett') {
    throw "Unexpected signer: $($sig.SignerCertificate.Subject)"
}
Write-Ok "Signed by: $($sig.SignerCertificate.Subject)"

Write-Step 'Installing HP CMSL'
$proc = Start-Process -FilePath $installer `
    -ArgumentList '/VERYSILENT', '/SP-', '/NORESTART', '/SUPPRESSMSGBOXES' `
    -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "Installer returned exit code $($proc.ExitCode). See InnoSetup exit code documentation."
}
Write-Ok 'Installed'

# The EXE installs into the Windows PowerShell 5.1 module path
# ($env:ProgramFiles\WindowsPowerShell\Modules), which is already on the default
# module search path for 5.1 -- no copying required.

if ($SetExecutionPolicy) {
    Write-Step 'Setting LocalMachine execution policy to RemoteSigned'
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
    Write-Ok 'Done'
}

# --- 2. Verify ------------------------------------------------------------
# Run the check in a clean, non-elevated-agnostic Windows PowerShell 5.1 child
# process -- the same runtime Clear-BiosPw.ps1 uses -- so this confirms the
# module resolves from a fresh session, not just this one.

Write-Step 'Verifying the BIOS password cmdlets under Windows PowerShell 5.1'

$verify = @'
Import-Module HP.ClientManagement -ErrorAction Stop
$cmdlets = 'Get-HPBIOSSetupPasswordIsSet','Clear-HPBIOSSetupPassword',
           'Set-HPBIOSSetupPassword','Get-HPBIOSPowerOnPasswordIsSet',
           'Get-HPBIOSVersion','Get-HPBIOSSettingsList'
foreach ($c in $cmdlets) {
    $found = [bool](Get-Command $c -ErrorAction SilentlyContinue)
    '{0,-32} {1}' -f $c, $(if ($found) { 'OK' } else { 'MISSING' })
}
'CMSL version: ' + (Get-Module HP.ClientManagement).Version
'@

$verifyFile = Join-Path $InstallPath 'verify.ps1'
Set-Content -Path $verifyFile -Value $verify -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyFile

Write-Step 'Bench setup complete'
Write-Host @"

    Open a NEW elevated Windows PowerShell 5.1 window before using the module.

    Audit a unit on the bench:
        Import-Module HP.ClientManagement
        Get-HPBIOSVersion
        Get-HPBIOSSetupPasswordIsSet
        Get-HPBIOSPowerOnPasswordIsSet

    Audit a unit over the network:
        Get-HPBIOSSetupPasswordIsSet -ComputerName HOSTNAME

    Clear a known password, then set your own:
        Clear-HPBIOSSetupPassword -Password 'currentpassword'
        Set-HPBIOSSetupPassword -NewPassword 'yournewpassword'

    Note: the cmdlets talk to HP's WMI provider, so each TARGET machine needs the
    HP notebook system BIOS driver installed. A clean Windows image without the HP
    driver pack will throw provider errors that look like a broken module.

"@ -ForegroundColor Gray

Stop-Transcript | Out-Null
