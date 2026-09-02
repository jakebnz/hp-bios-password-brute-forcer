<#
    Brute-forces the BIOS password on an HP notebook by trying a list of candidate passwords. The script
    uses the HP Client Management Script Library (CMSL) to attempt to clear the BIOS setup password
    and verify whether it was successful.

    The script is designed to be run repeatedly due to the 3-attempt lockout mechanism in the BIOS. It
    maintains a state file to remember which candidates have been tried for each unit's serial number.
    After attempting 3 candidates, the script will reboot the unit to reset the lockout. It is recommended
    to configure AutoAdminLogon and create a scheduled task to run the script automatically on login, so
    that it can continue trying candidates after each reboot without user intervention. When set up this way,
    the script can run unattended until it either succeeds or exhausts the candidate list.

    Pass -DisableAutoReboot to suppress the automatic reboot after 3 failed attempts. Progress is still
    saved, but the script exits cleanly and leaves the reboot to you (or your RMM); re-run it after the
    unit has rebooted to continue.

    The script must be called with the path to a text file containing candidate passwords, one per line
    (-PasswordFile); blank lines are ignored. -DisableAutoReboot is an optional switch.

    The state file and log file are stored under %ProgramData%\Clear-BiosPw. The state file is a JSON file that maps 
    serial numbers to the next untried index in the candidate list. The log file is a transcript of the script's output, 
    which can be useful for debugging or auditing. The script can be called with the -Verbose switch to see more detailed output,
    including exceptions raised by the CMSL cmdlets.

    Requirements:
    - HP Client Management Script Library (CMSL) installed on the unit.

    The following supplementary scripts are provided:
        install.ps1 is provided to install the CMSL and verify that the cmdlets are available in a fresh PowerShell session.
        fatfinger.ps1 is a utility to generate candidate password lists based on common typing errors (fat-fingered variants).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PasswordFile,

    # When set, the script does NOT auto-reboot after 3 failed attempts. It saves
    # progress and exits cleanly instead, leaving the reboot to you (or your RMM).
    [switch]$DisableAutoReboot
)

# --- Exit codes ------------------------------------------------------------
#   0  success, or stopped after a lockout (clean stop)
#   2  HP.ClientManagement module could not be imported
#   3  password file missing or empty
#   4  candidate list exhausted with no match
$ErrorActionPreference = 'Stop'

# --- Small colour helpers --------------------------------------------------
function Write-Ok   { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Fail { param([string]$Message) Write-Host $Message -ForegroundColor Red }
function Write-Warn { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }

# --- State file plumbing ---------------------------------------------------
# One JSON file under ProgramData holds a map of serial -> next untried index.
$StateDir  = Join-Path $env:ProgramData 'Clear-BiosPw'
$StateFile = Join-Path $StateDir 'state.json'

function Get-StateMap {
    # Returns a hashtable of serial -> index. Empty if no/invalid state file.
    if (-not (Test-Path -LiteralPath $StateFile)) { return @{} }
    try {
        $raw = Get-Content -LiteralPath $StateFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        $map = @{}
        # PSCustomObject from ConvertFrom-Json -> flatten into a hashtable.
        (ConvertFrom-Json $raw).PSObject.Properties | ForEach-Object {
            $map[$_.Name] = [int]$_.Value
        }
        return $map
    } catch {
        Write-Warn "State file was unreadable; starting fresh. ($($_.Exception.Message))"
        return @{}
    }
}

function Save-StateMap {
    param([hashtable]$Map)
    if (-not (Test-Path -LiteralPath $StateDir)) {
        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    }
    ($Map | ConvertTo-Json) | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function Set-SerialIndex {
    param([string]$Serial, [int]$Index)
    $map = Get-StateMap
    $map[$Serial] = $Index
    Save-StateMap -Map $map
}

function Clear-SerialIndex {
    param([string]$Serial)
    $map = Get-StateMap
    if ($map.ContainsKey($Serial)) {
        $map.Remove($Serial)
        Save-StateMap -Map $map
    }
}

# --- Start a transcript in the same folder as the state file ---------------
# One log file, appended to across runs. The try/finally below guarantees
# Stop-Transcript runs on every exit path (exit triggers finally).
if (-not (Test-Path -LiteralPath $StateDir)) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
}
$TranscriptFile = Join-Path $StateDir 'Clear-BiosPw.log'
Start-Transcript -LiteralPath $TranscriptFile -Append | Out-Null
Write-Host "Logging transcript to: $TranscriptFile"

try {

# --- 1. Import the HP module ----------------------------------------------
try {
    Import-Module HP.ClientManagement -ErrorAction Stop
} catch {
    Write-Fail "Could not import HP.ClientManagement. Install the HP Client Management Script Library and run again."
    Write-Fail "Reason: $($_.Exception.Message)"
    exit 2
}

# --- 2. Read the candidate list -------------------------------------------
if (-not (Test-Path -LiteralPath $PasswordFile)) {
    Write-Fail "Password file not found: $PasswordFile"
    exit 3
}

# Non-blank lines only, trimmed of trailing whitespace but preserving the value.
$candidates = @(
    Get-Content -LiteralPath $PasswordFile |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.TrimEnd("`r","`n") }
)

if ($candidates.Count -eq 0) {
    Write-Fail "Password file has no usable (non-blank) lines: $PasswordFile"
    exit 3
}

# --- 3. Identify the unit and work out the resume point --------------------
$serial = $null
try {
    $serial = (Get-HPBIOSSerialNumber -ErrorAction Stop)
} catch {
    try {
        $serial = (Get-HPDeviceSerialNumber -ErrorAction Stop)
    } catch {
        Write-Fail "Could not read this unit's serial number from the BIOS."
        Write-Fail "Reason: $($_.Exception.Message)"
        exit 2
    }
}
$serial = "$serial".Trim()
Write-Host "Unit serial: $serial"

$state = Get-StateMap
$startIndex = 0
if ($state.ContainsKey($serial)) {
    $startIndex = [int]$state[$serial]
}

# If a saved index has run past the list (e.g. list shortened), start fresh.
if ($startIndex -ge $candidates.Count) {
    Write-Warn "Saved position ($startIndex) is beyond the candidate list; starting from the top."
    $startIndex = 0
    Clear-SerialIndex -Serial $serial
}

if ($startIndex -gt 0) {
    Write-Warn "Resuming for serial $serial at candidate line $($startIndex + 1) (skipping $startIndex already-tried)."
} else {
    Write-Host "Starting from the first candidate."
}

# --- Guard: is a setup password even set right now? ------------------------
# If it's already clear, there is nothing to do.
if (-not (Get-HPBIOSSetupPasswordIsSet)) {
    Write-Ok "No BIOS setup password is currently set on this unit. Nothing to clear."
    Clear-SerialIndex -Serial $serial
    exit 0
}

# --- 4 & 5. Try candidates, verify, and honour the 3-attempt lockout -------
$failuresThisRun = 0
$locked = $false
$success = $false
$firstAttempt = $true
$i = $startIndex

while ($i -lt $candidates.Count) {
    $candidate = $candidates[$i]
    $lineNo    = $i + 1

    # Random pause between attempts (not before the first): 2-8 seconds, to the
    # millisecond. Get-Random's max is exclusive, so 2000..8000 ms inclusive.
    if (-not $firstAttempt) {
        $delayMs = Get-Random -Minimum 2000 -Maximum 8001
        Write-Host ("Waiting {0:N3}s before the next attempt..." -f ($delayMs / 1000))
        Start-Sleep -Milliseconds $delayMs
    }
    $firstAttempt = $false

    Write-Host "Trying candidate on line $lineNo ..."

    # Attempt the clear. A wrong password typically throws; swallow it here and
    # let the verification below be the authoritative test of success.
    try {
        Clear-HPBIOSSetupPassword -Password $candidate -ErrorAction Stop | Out-Null
    } catch {
        Write-Verbose "Clear-HPBIOSSetupPassword raised: $($_.Exception.Message)"
    }

    # Verify: success is defined as "the setup password is no longer set".
    $stillSet = $true
    try {
        $stillSet = [bool](Get-HPBIOSSetupPasswordIsSet)
    } catch {
        Write-Verbose "Get-HPBIOSSetupPasswordIsSet raised: $($_.Exception.Message)"
        $stillSet = $true
    }

    if (-not $stillSet) {
        $success = $true
        Write-Ok "SUCCESS: the password on line $lineNo cleared the BIOS setup password."
        Clear-SerialIndex -Serial $serial
        break
    }

    # Failure for this candidate.
    Write-Fail "Line $lineNo did not work."
    $failuresThisRun++
    $i++   # advance to the next untried candidate

    if ($failuresThisRun -ge 3) {
        # Persist the next untried index so a re-run resumes here.
        Set-SerialIndex -Serial $serial -Index $i
        $locked = $true

        Write-Warn "3 failed attempts. The BIOS may now be locked and needs a reboot before more attempts."
        Write-Warn "Progress saved for serial $serial (next candidate: line $($i + 1) of $($candidates.Count))."

        if ($DisableAutoReboot) {
            Write-Warn "Auto-reboot disabled (-DisableAutoReboot). Reboot manually, then re-run to continue."
        } else {
            Write-Warn "Rebooting now..."
            shutdown /r /f /t 5
        }
        break
    }
}

# --- Decide the exit --------------------------------------------------------
if ($success) {
    exit 0
}

if ($locked) {
    # Stopped on lockout; progress already saved. Clean exit either way.
    exit 0
}

# --- 6. Candidate list exhausted with no success ---------------------------
Write-Fail "None of the $($candidates.Count) candidate passwords cleared the BIOS setup password."
Clear-SerialIndex -Serial $serial   # so a fresh run starts from the top
exit 4

}
finally {
    # Always close the transcript, whatever exit path we took.
    Stop-Transcript | Out-Null
}
