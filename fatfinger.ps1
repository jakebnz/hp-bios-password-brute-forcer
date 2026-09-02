<#
.DESCRIPTION
    Produces every conceivable mistyped version of a string by simulating real
    keyboard errors: adjacent-key hits, transpositions, double presses, caps lock,
    shift-symbol swaps, omissions, insertions, hand-offset, numpad adjacency,
    mobile keyboard quirks, and many multi-error combinations.

    Output scales with string length and complexity. A 14-character mixed
    alphanumeric string typically yields 7,000+ unique variations.

.PARAMETER InputString
    The string to generate fat-finger variations for.

.PARAMETER OutputFile
    Optional. Write results to this file path instead of stdout.

.PARAMETER IncludeCombos
    Include multi-error combination categories (substitution+transposition,
    omission+capitalisation, etc.). On by default. Disable with -IncludeCombos:$false
    for a smaller, faster run.

.EXAMPLE
    .\FatFinger.ps1 -InputString "123fmip3"

.EXAMPLE
    .\FatFinger.ps1 -InputString "P@ssw0rd!" -OutputFile "variations.txt"

.EXAMPLE
    .\FatFinger.ps1 "MySecret123" | Measure-Object -Line
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$InputString,

    [Parameter()]
    [string]$OutputFile,

    [Parameter()]
    [bool]$IncludeCombos = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ──────────────────────────────────────────────────────────────
# Keyboard maps
# ──────────────────────────────────────────────────────────────

$QwertyAdjacent = @{
    'q' = @('w','a','1','2','`')
    'w' = @('q','e','a','s','2','3')
    'e' = @('w','r','s','d','3','4')
    'r' = @('e','t','d','f','4','5')
    't' = @('r','y','f','g','5','6')
    'y' = @('t','u','g','h','6','7')
    'u' = @('y','i','h','j','7','8')
    'i' = @('u','o','j','k','8','9')
    'o' = @('i','p','k','l','9','0')
    'p' = @('o','[','l',';','0','-')
    'a' = @('q','w','s','z')
    's' = @('a','d','w','e','z','x')
    'd' = @('s','f','e','r','x','c')
    'f' = @('d','g','r','t','c','v')
    'g' = @('f','h','t','y','v','b')
    'h' = @('g','j','y','u','b','n')
    'j' = @('h','k','u','i','n','m')
    'k' = @('j','l','i','o','m',',')
    'l' = @('k',';','o','p',',','.')
    'z' = @('a','s','x')
    'x' = @('z','c','s','d')
    'c' = @('x','v','d','f')
    'v' = @('c','b','f','g')
    'b' = @('v','n','g','h')
    'n' = @('b','m','h','j')
    'm' = @('n',',','j','k')
    '1' = @('2','q','`')
    '2' = @('1','3','q','w')
    '3' = @('2','4','w','e')
    '4' = @('3','5','e','r')
    '5' = @('4','6','r','t')
    '6' = @('5','7','t','y')
    '7' = @('6','8','y','u')
    '8' = @('7','9','u','i')
    '9' = @('8','0','i','o')
    '0' = @('9','-','o','p')
    '-' = @('0','=','p','[')
    '=' = @('-','[',']')
    '[' = @('p',']',';',"'",'-','=')
    ']' = @('[','\','=')
    ';' = @('l',"'",'p','[',',','.')
    "'" = @(';','[',']','.','/');
    ',' = @('k','l','m','.')
    '.' = @(',','/',';',"'",'l')
    '/' = @('.',';',"'")
    '`' = @('1','q')
    '\' = @(']')
}

$ShiftSymbols = @{
    '1' = '!'; '2' = '@'; '3' = '#'; '4' = '$'; '5' = '%'
    '6' = '^'; '7' = '&'; '8' = '*'; '9' = '('; '0' = ')'
    '-' = '_'; '=' = '+'; '[' = '{'; ']' = '}'; '\' = '|'
    ';' = ':'; "'" = '"'; ',' = '<'; '.' = '>'; '/' = '?'
    '`' = '~'
}

$NumpadAdjacent = @{
    '0' = @('1','2','.')
    '1' = @('0','2','4','5')
    '2' = @('0','1','3','4','5','6')
    '3' = @('2','5','6')
    '4' = @('1','2','5','7','8')
    '5' = @('1','2','3','4','6','7','8','9')
    '6' = @('2','3','5','8','9')
    '7' = @('4','5','8')
    '8' = @('4','5','6','7','9')
    '9' = @('5','6','8')
}

$RightShift = @{
    'q'='w';'w'='e';'e'='r';'r'='t';'t'='y';'y'='u';'u'='i';'i'='o';'o'='p'
    'a'='s';'s'='d';'d'='f';'f'='g';'g'='h';'h'='j';'j'='k';'k'='l'
    'z'='x';'x'='c';'c'='v';'v'='b';'b'='n';'n'='m'
    '1'='2';'2'='3';'3'='4';'4'='5';'5'='6';'6'='7';'7'='8';'8'='9';'9'='0'
}
$LeftShift = @{}
foreach ($k in $RightShift.Keys) { $LeftShift[$RightShift[$k]] = $k }

$RowAbove = @{
    'a'='q';'s'='w';'d'='e';'f'='r';'g'='t';'h'='y';'j'='u';'k'='i';'l'='o'
    'z'='a';'x'='s';'c'='d';'v'='f';'b'='g';'n'='h';'m'='j'
}
$RowBelow = @{}
foreach ($k in $RowAbove.Keys) { $RowBelow[$RowAbove[$k]] = $k }

# ──────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────

function ReplaceAt([string]$s, [int]$i, [string]$c) {
    if ($i -eq 0)          { return $c + $s.Substring(1) }
    if ($i -eq $s.Length-1) { return $s.Substring(0,$i) + $c }
    return $s.Substring(0,$i) + $c + $s.Substring($i+1)
}

function RemoveAt([string]$s, [int]$i) {
    if ($i -eq 0)          { return $s.Substring(1) }
    if ($i -eq $s.Length-1) { return $s.Substring(0,$i) }
    return $s.Substring(0,$i) + $s.Substring($i+1)
}

function InsertAt([string]$s, [int]$i, [string]$c) {
    return $s.Substring(0,$i) + $c + $s.Substring($i)
}

function SwapAt([string]$s, [int]$i, [int]$j) {
    $arr = $s.ToCharArray()
    $tmp = $arr[$i]; $arr[$i] = $arr[$j]; $arr[$j] = $tmp
    return [string]::new($arr)
}

function GetAdjacent([char]$c) {
    $key = [string]$c
    # Unary-comma return keeps the result an array through PowerShell's pipeline
    # unroll, so single-element lists (e.g. '\' -> ']') don't collapse to a scalar
    # and break the .Count checks under StrictMode.
    if ($QwertyAdjacent.ContainsKey($key)) { return ,$QwertyAdjacent[$key] }
    # Try lowercase
    $lower = $key.ToLower()
    if ($QwertyAdjacent.ContainsKey($lower)) { return ,$QwertyAdjacent[$lower] }
    return ,@()
}

# ──────────────────────────────────────────────────────────────
# Collect variations
# ──────────────────────────────────────────────────────────────

$Variants = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$src = $InputString
$L   = $src.Length

function Add-Variant([string]$v) {
    # Use -cne (case-sensitive) so case-only variants aren't discarded as equal
    # to the source; the HashSet is Ordinal, so we keep the comparison Ordinal too.
    if ($v -and $v -cne $src -and $v.Length -gt 0) {
        [void]$Variants.Add($v)
    }
}

Write-Host "Generating fat-finger variations for: $src" -ForegroundColor Cyan
Write-Host "String length: $L characters" -ForegroundColor DarkGray

# Track progress
$categoryCount = 0
function Start-Category([string]$name) {
    $script:categoryCount++
    $before = $Variants.Count
    Write-Host "  [$script:categoryCount] $name..." -ForegroundColor DarkGray -NoNewline
    return $before
}
function End-Category([int]$before) {
    $added = $Variants.Count - $before
    Write-Host " +$added" -ForegroundColor DarkYellow
}

# ═══════════════════════════════════════════════════════════════
# CATEGORY 1: Single adjacent key substitution
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Single adjacent key substitution"
for ($i = 0; $i -lt $L; $i++) {
    foreach ($rep in (GetAdjacent $src[$i])) {
        Add-Variant (ReplaceAt $src $i $rep)
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 2: Double adjacent key substitution (two errors)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Double adjacent key substitution"
for ($i = 0; $i -lt $L; $i++) {
    $adjI = GetAdjacent $src[$i]
    if ($adjI.Count -eq 0) { continue }
    foreach ($repI in $adjI) {
        $base = ReplaceAt $src $i $repI
        for ($j = $i + 1; $j -lt $L; $j++) {
            $adjJ = GetAdjacent $base[$j]
            if ($adjJ.Count -eq 0) { continue }
            foreach ($repJ in $adjJ) {
                Add-Variant (ReplaceAt $base $j $repJ)
            }
        }
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 3: Single character omission
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Single character omission"
for ($i = 0; $i -lt $L; $i++) {
    Add-Variant (RemoveAt $src $i)
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 4: Double character omission
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Double character omission"
for ($i = 0; $i -lt $L; $i++) {
    $base = RemoveAt $src $i
    for ($j = 0; $j -lt $base.Length; $j++) {
        Add-Variant (RemoveAt $base $j)
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 5: Adjacent transposition
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Adjacent transposition"
for ($i = 0; $i -lt ($L - 1); $i++) {
    Add-Variant (SwapAt $src $i ($i+1))
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 6: Non-adjacent transposition (gap 2-4)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Non-adjacent transposition"
for ($i = 0; $i -lt $L; $i++) {
    for ($j = $i + 2; $j -lt [Math]::Min($i + 5, $L); $j++) {
        Add-Variant (SwapAt $src $i $j)
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 7: Double transposition
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Double transposition"
for ($i = 0; $i -lt ($L - 1); $i++) {
    $base = SwapAt $src $i ($i + 1)
    for ($j = $i + 2; $j -lt ($L - 1); $j++) {
        Add-Variant (SwapAt $base $j ($j + 1))
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 8: Double press (character duplication)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Double press"
for ($i = 0; $i -lt $L; $i++) {
    Add-Variant (InsertAt $src $i ([string]$src[$i]))
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 9: Triple press
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Triple press"
for ($i = 0; $i -lt $L; $i++) {
    $ch = [string]$src[$i]
    Add-Variant ($src.Substring(0,$i) + $ch + $ch + $src.Substring($i))
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 10: Stutter (repeat current instead of typing next)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Stutter repeat"
for ($i = 0; $i -lt ($L - 1); $i++) {
    Add-Variant (ReplaceAt $src ($i + 1) ([string]$src[$i]))
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 11: Single character capitalisation
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Single capitalisation"
for ($i = 0; $i -lt $L; $i++) {
    if ([char]::IsLetter($src[$i])) {
        $toggled = if ([char]::IsUpper($src[$i])) { [char]::ToLower($src[$i]) } else { [char]::ToUpper($src[$i]) }
        Add-Variant (ReplaceAt $src $i ([string]$toggled))
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 12: Two character capitalisation (all pairs)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Two character capitalisation"
$alphaPos = @(for ($i = 0; $i -lt $L; $i++) { if ([char]::IsLetter($src[$i])) { $i } })
for ($a = 0; $a -lt $alphaPos.Count; $a++) {
    for ($bb = $a + 1; $bb -lt $alphaPos.Count; $bb++) {
        $arr = $src.ToCharArray()
        $idx1 = $alphaPos[$a]; $idx2 = $alphaPos[$bb]
        $arr[$idx1] = if ([char]::IsUpper($arr[$idx1])) { [char]::ToLower($arr[$idx1]) } else { [char]::ToUpper($arr[$idx1]) }
        $arr[$idx2] = if ([char]::IsUpper($arr[$idx2])) { [char]::ToLower($arr[$idx2]) } else { [char]::ToUpper($arr[$idx2]) }
        Add-Variant ([string]::new($arr))
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 13: Three character capitalisation (all triples)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Three character capitalisation"
for ($a = 0; $a -lt $alphaPos.Count; $a++) {
    for ($bb = $a + 1; $bb -lt $alphaPos.Count; $bb++) {
        for ($cc = $bb + 1; $cc -lt $alphaPos.Count; $cc++) {
            $arr = $src.ToCharArray()
            foreach ($idx in @($alphaPos[$a], $alphaPos[$bb], $alphaPos[$cc])) {
                $arr[$idx] = if ([char]::IsUpper($arr[$idx])) { [char]::ToLower($arr[$idx]) } else { [char]::ToUpper($arr[$idx]) }
            }
            Add-Variant ([string]::new($arr))
        }
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 14: Caps lock runs (on from position X to Y)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Caps lock runs"
for ($start = 0; $start -lt $L; $start++) {
    for ($end = $start + 1; $end -le $L; $end++) {
        $arr = $src.ToCharArray()
        for ($k = $start; $k -lt $end; $k++) {
            if ([char]::IsLetter($arr[$k])) {
                $arr[$k] = if ([char]::IsUpper($arr[$k])) { [char]::ToLower($arr[$k]) } else { [char]::ToUpper($arr[$k]) }
            }
        }
        Add-Variant ([string]::new($arr))
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 15: All caps / all lowercase toggle
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Full case toggle"
Add-Variant $src.ToUpper()
Add-Variant $src.ToLower()
# All letters toggled
$arr = $src.ToCharArray()
for ($i = 0; $i -lt $arr.Length; $i++) {
    if ([char]::IsUpper($arr[$i])) { $arr[$i] = [char]::ToLower($arr[$i]) }
    elseif ([char]::IsLower($arr[$i])) { $arr[$i] = [char]::ToUpper($arr[$i]) }
}
Add-Variant ([string]::new($arr))
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 16: Shift-symbol substitution (single)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Shift-symbol substitution (single)"
for ($i = 0; $i -lt $L; $i++) {
    $key = [string]$src[$i]
    if ($ShiftSymbols.ContainsKey($key)) {
        Add-Variant (ReplaceAt $src $i $ShiftSymbols[$key])
    }
    # Reverse: if char IS a symbol, try the unshifted version
    foreach ($k in $ShiftSymbols.Keys) {
        if ($ShiftSymbols[$k] -ceq $key) {
            Add-Variant (ReplaceAt $src $i $k)
        }
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 17: Shift-symbol substitution (all pairs)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Shift-symbol substitution (pairs)"
$shiftablePos = @(for ($i = 0; $i -lt $L; $i++) { if ($ShiftSymbols.ContainsKey([string]$src[$i])) { $i } })
for ($a = 0; $a -lt $shiftablePos.Count; $a++) {
    for ($bb = $a + 1; $bb -lt $shiftablePos.Count; $bb++) {
        $arr = $src.ToCharArray()
        $arr[$shiftablePos[$a]] = [char]$ShiftSymbols[[string]$arr[$shiftablePos[$a]]]
        $arr[$shiftablePos[$bb]] = [char]$ShiftSymbols[[string]$arr[$shiftablePos[$bb]]]
        Add-Variant ([string]::new($arr))
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 18: All shiftable characters shifted
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "All shifted"
$arr = $src.ToCharArray()
$changed = $false
for ($i = 0; $i -lt $arr.Length; $i++) {
    $key = [string]$arr[$i]
    if ($ShiftSymbols.ContainsKey($key)) { $arr[$i] = [char]$ShiftSymbols[$key]; $changed = $true }
}
if ($changed) { Add-Variant ([string]::new($arr)) }
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 19: Extra adjacent key inserted (before and after)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Extra adjacent key inserted"
for ($i = 0; $i -lt $L; $i++) {
    foreach ($extra in (GetAdjacent $src[$i])) {
        Add-Variant (InsertAt $src $i $extra)          # before
        Add-Variant (InsertAt $src ($i + 1) $extra)    # after
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 20: Space inserted / replacing
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Space errors"
for ($i = 0; $i -le $L; $i++) {
    Add-Variant (InsertAt $src $i ' ')
}
for ($i = 0; $i -lt $L; $i++) {
    Add-Variant (ReplaceAt $src $i ' ')
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 21: Trailing / leading garbage (full keyboard)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Trailing/leading garbage"
$garbageChars = '1234567890-=qwertyuiop[]\asdfghjkl;zxcvbnm,./`~!@#$%^&*()_+ '.ToCharArray() | Select-Object -Unique
foreach ($ch in $garbageChars) {
    Add-Variant ($src + $ch)
    Add-Variant ([string]$ch + $src)
}
# Double trailing/leading
foreach ($ch in '1234567890 .-/'.ToCharArray()) {
    Add-Variant ($src + $ch + $ch)
    Add-Variant ([string]$ch + [string]$ch + $src)
    foreach ($ch2 in '1234567890'.ToCharArray()) {
        Add-Variant ($src + $ch + $ch2)
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 22: Numpad adjacency substitution
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Numpad adjacency (single)"
for ($i = 0; $i -lt $L; $i++) {
    $key = [string]$src[$i]
    if ($NumpadAdjacent.ContainsKey($key)) {
        foreach ($rep in $NumpadAdjacent[$key]) {
            Add-Variant (ReplaceAt $src $i $rep)
        }
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 23: Double numpad adjacency
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Numpad adjacency (double)"
$digitPos = @(for ($i = 0; $i -lt $L; $i++) { if ([char]::IsDigit($src[$i])) { $i } })
for ($a = 0; $a -lt $digitPos.Count; $a++) {
    $iPos = $digitPos[$a]
    $key1 = [string]$src[$iPos]
    if (-not $NumpadAdjacent.ContainsKey($key1)) { continue }
    foreach ($r1 in $NumpadAdjacent[$key1]) {
        $base = ReplaceAt $src $iPos $r1
        for ($bb = $a + 1; $bb -lt $digitPos.Count; $bb++) {
            $jPos = $digitPos[$bb]
            $key2 = [string]$base[$jPos]
            if (-not $NumpadAdjacent.ContainsKey($key2)) { continue }
            foreach ($r2 in $NumpadAdjacent[$key2]) {
                Add-Variant (ReplaceAt $base $jPos $r2)
            }
        }
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 24: Hand shifted left / right (full and partial)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Hand shifted left/right"
# Full shift
$arrR = $src.ToCharArray(); $arrL = $src.ToCharArray()
for ($i = 0; $i -lt $L; $i++) {
    $k = ([string]$arrR[$i]).ToLower()
    if ($RightShift.ContainsKey($k)) { $arrR[$i] = [char]$RightShift[$k] }
    if ($LeftShift.ContainsKey($k))  { $arrL[$i] = [char]$LeftShift[$k] }
}
Add-Variant ([string]::new($arrR))
Add-Variant ([string]::new($arrL))

# Partial shift: first N or last N
for ($n = 1; $n -lt $L; $n++) {
    # Right-shift first N
    $arr = $src.ToCharArray()
    for ($i = 0; $i -lt $n; $i++) {
        $k = ([string]$arr[$i]).ToLower()
        if ($RightShift.ContainsKey($k)) { $arr[$i] = [char]$RightShift[$k] }
    }
    Add-Variant ([string]::new($arr))

    # Right-shift last N
    $arr = $src.ToCharArray()
    for ($i = $L - $n; $i -lt $L; $i++) {
        $k = ([string]$arr[$i]).ToLower()
        if ($RightShift.ContainsKey($k)) { $arr[$i] = [char]$RightShift[$k] }
    }
    Add-Variant ([string]::new($arr))

    # Left-shift first N
    $arr = $src.ToCharArray()
    for ($i = 0; $i -lt $n; $i++) {
        $k = ([string]$arr[$i]).ToLower()
        if ($LeftShift.ContainsKey($k)) { $arr[$i] = [char]$LeftShift[$k] }
    }
    Add-Variant ([string]::new($arr))

    # Left-shift last N
    $arr = $src.ToCharArray()
    for ($i = $L - $n; $i -lt $L; $i++) {
        $k = ([string]$arr[$i]).ToLower()
        if ($LeftShift.ContainsKey($k)) { $arr[$i] = [char]$LeftShift[$k] }
    }
    Add-Variant ([string]::new($arr))
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 25: Row above / row below substitution
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Row above/below substitution"
for ($i = 0; $i -lt $L; $i++) {
    $key = ([string]$src[$i]).ToLower()
    if ($RowAbove.ContainsKey($key)) { Add-Variant (ReplaceAt $src $i $RowAbove[$key]) }
    if ($RowBelow.ContainsKey($key)) { Add-Variant (ReplaceAt $src $i $RowBelow[$key]) }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 26: Reversed segments
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Reversed segments"
Add-Variant ($src[-1..-$L] -join '')  # fully reversed
# Sliding window reversals (length 2-6)
for ($start = 0; $start -lt $L; $start++) {
    for ($winLen = 2; $winLen -le [Math]::Min(6, $L - $start); $winLen++) {
        $before  = $src.Substring(0, $start)
        $segment = $src.Substring($start, $winLen)
        $after   = $src.Substring($start + $winLen)
        $reversed = ($segment[-1..-$segment.Length] -join '')
        Add-Variant ($before + $reversed + $after)
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 27: Digit permutations (if digits exist)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Digit sequence permutations"
# Find contiguous digit runs
$digitRuns = [System.Collections.Generic.List[int[]]]::new()
$runStart = -1
for ($i = 0; $i -le $L; $i++) {
    if ($i -lt $L -and [char]::IsDigit($src[$i])) {
        if ($runStart -eq -1) { $runStart = $i }
    } else {
        if ($runStart -ne -1) {
            $digitRuns.Add([int[]]@($runStart, ($i - 1)))
            $runStart = -1
        }
    }
}

foreach ($run in $digitRuns) {
    $rs = $run[0]; $re = $run[1]
    $runLen = $re - $rs + 1
    if ($runLen -ge 2 -and $runLen -le 8) {
        # Generate permutations (cap at 7 digits to avoid explosion)
        $digits = $src.Substring($rs, $runLen).ToCharArray()
        $perms = [System.Collections.Generic.HashSet[string]]::new()
        # Simple permutation via iteration for small sets
        function Get-Permutations([char[]]$arr, [int]$start) {
            if ($start -eq $arr.Length - 1) {
                [void]$perms.Add([string]::new($arr))
                return
            }
            for ($ii = $start; $ii -lt $arr.Length; $ii++) {
                $tmp = $arr[$start]; $arr[$start] = $arr[$ii]; $arr[$ii] = $tmp
                Get-Permutations $arr ($start + 1)
                $tmp = $arr[$start]; $arr[$start] = $arr[$ii]; $arr[$ii] = $tmp
            }
        }
        if ($runLen -le 7) {
            Get-Permutations $digits 0
            foreach ($p in $perms) {
                Add-Variant ($src.Substring(0, $rs) + $p + $src.Substring($re + 1))
            }
        }
    }
    # Individual digit increment/decrement
    for ($i = $rs; $i -le $re; $i++) {
        $d = [int]::Parse([string]$src[$i])
        foreach ($delta in @(-2, -1, 1, 2)) {
            $nd = $d + $delta
            if ($nd -ge 0 -and $nd -le 9) {
                Add-Variant (ReplaceAt $src $i ([string]$nd))
            }
        }
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 28: Truncated (partial typing)
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Partial typing (truncated)"
for ($i = 1; $i -lt $L; $i++) {
    Add-Variant $src.Substring(0, $i)
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 29: Separator insertion at character class boundaries
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Boundary separator insertion"
$separators = @('-', '_', '.', '/', '\', ' ', '#', '@', '+')
for ($i = 1; $i -lt $L; $i++) {
    $prev = $src[$i - 1]; $curr = $src[$i]
    $classChange = ([char]::IsLetter($prev) -ne [char]::IsLetter($curr)) -or
                   ([char]::IsDigit($prev) -ne [char]::IsDigit($curr)) -or
                   ([char]::IsUpper($prev) -ne [char]::IsUpper($curr) -and [char]::IsLetter($prev) -and [char]::IsLetter($curr))
    if ($classChange) {
        foreach ($sep in $separators) {
            Add-Variant (InsertAt $src $i $sep)
        }
        # Boundary char duplication
        Add-Variant (InsertAt $src $i ([string]$src[$i - 1]))
        Add-Variant (InsertAt $src $i ([string]$src[$i]))
    }
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 30: Repeated string fragments
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Repeated fragments"
for ($fragLen = 1; $fragLen -le [Math]::Min(4, $L); $fragLen++) {
    Add-Variant ($src.Substring(0, $fragLen) + $src)
    Add-Variant ($src + $src.Substring($L - $fragLen))
}
End-Category $b

# ═══════════════════════════════════════════════════════════════
# CATEGORY 31: Double press at two positions
# ═══════════════════════════════════════════════════════════════
$b = Start-Category "Double press at two positions"
for ($i = 0; $i -lt $L; $i++) {
    $base = InsertAt $src $i ([string]$src[$i])
    for ($j = $i + 2; $j -lt $base.Length; $j++) {
        Add-Variant (InsertAt $base $j ([string]$base[$j]))
    }
}
End-Category $b

# ══════════════════════════════════════════════════════════════
# COMBINATION CATEGORIES (multi-error)
# ══════════════════════════════════════════════════════════════

if ($IncludeCombos) {

    # ═══════════════════════════════════════════════════════════
    # COMBO 1: Substitution + transposition
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: substitution + transposition"
    for ($i = 0; $i -lt $L; $i++) {
        foreach ($rep in (GetAdjacent $src[$i])) {
            $base = ReplaceAt $src $i $rep
            for ($j = 0; $j -lt ($base.Length - 1); $j++) {
                Add-Variant (SwapAt $base $j ($j + 1))
            }
        }
    }
    End-Category $b

    # ═══════════════════════════════════════════════════════════
    # COMBO 2: Substitution + omission
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: substitution + omission"
    for ($i = 0; $i -lt $L; $i++) {
        $adj = GetAdjacent $src[$i]
        if ($adj.Count -eq 0) { continue }
        foreach ($rep in $adj[0..([Math]::Min(2, $adj.Count - 1))]) {
            $base = ReplaceAt $src $i $rep
            for ($j = 0; $j -lt $base.Length; $j++) {
                if ($j -ne $i) { Add-Variant (RemoveAt $base $j) }
            }
        }
    }
    End-Category $b

    # ═══════════════════════════════════════════════════════════
    # COMBO 3: Substitution + capitalisation
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: substitution + capitalisation"
    for ($i = 0; $i -lt $L; $i++) {
        foreach ($rep in (GetAdjacent $src[$i])) {
            $base = ReplaceAt $src $i $rep
            for ($j = 0; $j -lt $base.Length; $j++) {
                if ([char]::IsLetter($base[$j])) {
                    $toggled = if ([char]::IsUpper($base[$j])) { [char]::ToLower($base[$j]) } else { [char]::ToUpper($base[$j]) }
                    Add-Variant (ReplaceAt $base $j ([string]$toggled))
                }
            }
        }
    }
    End-Category $b

    # ═══════════════════════════════════════════════════════════
    # COMBO 4: Omission + transposition
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: omission + transposition"
    for ($i = 0; $i -lt $L; $i++) {
        $base = RemoveAt $src $i
        for ($j = 0; $j -lt ($base.Length - 1); $j++) {
            Add-Variant (SwapAt $base $j ($j + 1))
        }
    }
    End-Category $b

    # ═══════════════════════════════════════════════════════════
    # COMBO 5: Omission + capitalisation
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: omission + capitalisation"
    for ($i = 0; $i -lt $L; $i++) {
        $base = RemoveAt $src $i
        for ($j = 0; $j -lt $base.Length; $j++) {
            if ([char]::IsLetter($base[$j])) {
                $toggled = if ([char]::IsUpper($base[$j])) { [char]::ToLower($base[$j]) } else { [char]::ToUpper($base[$j]) }
                Add-Variant (ReplaceAt $base $j ([string]$toggled))
            }
        }
    }
    End-Category $b

    # ═══════════════════════════════════════════════════════════
    # COMBO 6: Double press + substitution
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: double press + substitution"
    for ($i = 0; $i -lt $L; $i++) {
        $base = InsertAt $src $i ([string]$src[$i])
        for ($j = 0; $j -lt $base.Length; $j++) {
            $adj = GetAdjacent $base[$j]
            if ($adj.Count -eq 0) { continue }
            foreach ($rep in $adj[0..([Math]::Min(1, $adj.Count - 1))]) {
                Add-Variant (ReplaceAt $base $j $rep)
            }
        }
    }
    End-Category $b

    # ═══════════════════════════════════════════════════════════
    # COMBO 7: Double press + transposition
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: double press + transposition"
    for ($i = 0; $i -lt $L; $i++) {
        $base = InsertAt $src $i ([string]$src[$i])
        for ($j = 0; $j -lt ($base.Length - 1); $j++) {
            Add-Variant (SwapAt $base $j ($j + 1))
        }
    }
    End-Category $b

    # ═══════════════════════════════════════════════════════════
    # COMBO 8: Double press + capitalisation
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: double press + capitalisation"
    for ($i = 0; $i -lt $L; $i++) {
        $base = InsertAt $src $i ([string]$src[$i])
        for ($j = 0; $j -lt $base.Length; $j++) {
            if ([char]::IsLetter($base[$j])) {
                $toggled = if ([char]::IsUpper($base[$j])) { [char]::ToLower($base[$j]) } else { [char]::ToUpper($base[$j]) }
                Add-Variant (ReplaceAt $base $j ([string]$toggled))
            }
        }
    }
    End-Category $b

    # ═══════════════════════════════════════════════════════════
    # COMBO 9: Capitalisation + transposition
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: capitalisation + transposition"
    for ($i = 0; $i -lt $L; $i++) {
        if (-not [char]::IsLetter($src[$i])) { continue }
        $toggled = if ([char]::IsUpper($src[$i])) { [char]::ToLower($src[$i]) } else { [char]::ToUpper($src[$i]) }
        $base = ReplaceAt $src $i ([string]$toggled)
        for ($j = 0; $j -lt ($L - 1); $j++) {
            Add-Variant (SwapAt $base $j ($j + 1))
        }
    }
    End-Category $b

    # ═══════════════════════════════════════════════════════════
    # COMBO 10: Capitalisation + shift-symbol
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: capitalisation + shift-symbol"
    foreach ($ai in $alphaPos) {
        $toggled = if ([char]::IsUpper($src[$ai])) { [char]::ToLower($src[$ai]) } else { [char]::ToUpper($src[$ai]) }
        $base = ReplaceAt $src $ai ([string]$toggled)
        for ($j = 0; $j -lt $L; $j++) {
            $key = [string]$base[$j]
            if ($ShiftSymbols.ContainsKey($key)) {
                Add-Variant (ReplaceAt $base $j $ShiftSymbols[$key])
            }
        }
    }
    End-Category $b

    # ═══════════════════════════════════════════════════════════
    # COMBO 11: Shift-symbol + substitution
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: shift-symbol + substitution"
    for ($i = 0; $i -lt $L; $i++) {
        $key = [string]$src[$i]
        if (-not $ShiftSymbols.ContainsKey($key)) { continue }
        $base = ReplaceAt $src $i $ShiftSymbols[$key]
        for ($j = 0; $j -lt $base.Length; $j++) {
            $adj = GetAdjacent $base[$j]
            if ($adj.Count -eq 0) { continue }
            foreach ($rep in $adj[0..([Math]::Min(1, $adj.Count - 1))]) {
                Add-Variant (ReplaceAt $base $j $rep)
            }
        }
    }
    End-Category $b

    # ═══════════════════════════════════════════════════════════
    # COMBO 12: Omission + substitution
    # ═══════════════════════════════════════════════════════════
    $b = Start-Category "Combo: omission + substitution"
    for ($i = 0; $i -lt $L; $i++) {
        $base = RemoveAt $src $i
        for ($j = 0; $j -lt $base.Length; $j++) {
            $adj = GetAdjacent $base[$j]
            if ($adj.Count -eq 0) { continue }
            foreach ($rep in $adj[0..([Math]::Min(2, $adj.Count - 1))]) {
                Add-Variant (ReplaceAt $base $j $rep)
            }
        }
    }
    End-Category $b
}

# ──────────────────────────────────────────────────────────────
# Output
# ──────────────────────────────────────────────────────────────

Write-Host "`nTotal unique variations: $($Variants.Count)" -ForegroundColor Green

$sorted = $Variants | Sort-Object

if ($OutputFile) {
    $sorted | Set-Content -Path $OutputFile -Encoding UTF8
    Write-Host "Written to: $OutputFile" -ForegroundColor Green
} else {
    $sorted | ForEach-Object { $_ }
}