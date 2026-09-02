# HP BIOS Password Brute Forcer

Brute-forces the BIOS password on an HP laptops by trying a list of candidate passwords. The script
uses the HP Client Management Script Library (CMSL) to attempt to clear the BIOS setup password
and verify whether it was successful.

The script is designed to be run repeatedly due to the 3-attempt lockout mechanism in the BIOS. It
maintains a state file to remember which candidates have been tried for each unit's serial number.
After attempting 3 candidates, the script will reboot the unit to reset the lockout. It is recommended
to configure AutoAdminLogon and create a scheduled task to run the script automatically on login, so
that it can continue trying candidates after each reboot without user intervention. When set up this way,
the script can run unattended until it either succeeds or exhausts the candidate list.

The script was used to sucessfully clear a mistyped BIOS password on an HP EliteBook 840 G9 after 4,732 attempts.

> **DISCLAIMER:** Only use this on a device that is yours, or that you have explicit permission to access.
> Do not use it on a device that is not yours or that you do not have permission to unlock. It is only
> useful for recovering known passwords that were mistyped.

## Installation

The script relies on the HP CMSL powershell library to function. If you don't have this installed run `install.ps1` to install it and check that it's functioning.

The script requires a list of candidate passwords to be tried. The supplementary script `fatfinger.ps1` is provided to assist with creating this list. It will produce potential mistyped variations of the given string. When the script is called it must be passed a text file containing the candidate passwords, one per line. Blank lines are ignored.

To leave this running unattended you will need to configure the computer to run the script automatically at start up. One way to achieve this (and what was done in the test case) is configuring AutoAdminLogon in Windows to automatically sign in, and creating a scheduled task to run at logon that runs the script automatically. The task was also set to repeat every 5 minutes in case the script didn't start the first time.

## Usage

The script must be called with a single argument: the path to a text file containing candidate passwords,
one per line. Blank lines are ignored.

The state file and log file are stored under %ProgramData%\Clear-BiosPw. The state file is a JSON file that maps
serial numbers to the next untried index in the candidate list. The log file is a transcript of the script's output,
which can be useful for debugging or auditing. The script can be called with the -Verbose switch to see more detailed output,
including exceptions raised by the CMSL cmdlets.

An optional argument `-DisableAutoReboot` can be passed to disable the automatic reboot after 3 password attempts.

## Limitations

HP silently locks out bios password clearing attempts after 3 tries, so the computer needs to be rebooted after 3 attempts. This greatly slows down how quickly attempts can be made. On the devices used in the test case it took approximately 1 minute 27 seconds per cycle including the time needed to reboot. This translates to ~3000 attempts per 24 hour period.

The script also waits a randomised amount of time between attempting each password in order to avoid triggering any other brute-force detections, though there doesn't seem to be any other measures in place aside from the 3-attempt lockout.

> **DISCLAIMER, AGAIN:** Seriously, do not use this to try and crack open a stolen laptop. Aside from being illegal, it will not
> work even if you do.
