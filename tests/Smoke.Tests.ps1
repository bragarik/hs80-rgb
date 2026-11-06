# SPDX-License-Identifier: GPL-3.0-or-later
# No headset required. This also compiles the embedded C# controller.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'hs80-rgb.ps1'

function Assert-Equal($actual, $expected, [string]$description) {
    if ($actual -cne $expected) {
        throw ('{0}: expected [{1}], got [{2}]' -f $description, $expected, $actual)
    }
}

$tokens = $null
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile(
    $scriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }

$off = & $scriptPath -Preview
Assert-Equal $off.EffectiveColor '#000000' 'Default is off'
Assert-Equal $off.Reports.Count 5 'Five HID reports'
Assert-Equal $off.Reports[0] 'C8-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00' 'Mode reset'
Assert-Equal $off.Reports[1] 'C8-01-00-00-00-00-00-00-00-00-00-00-00-00-00-00' 'Software mode'
Assert-Equal $off.Reports[2] 'C9-64-00-00-00-00-00-00-00-00-00-00-00-00-00-00' 'LED init 1'
Assert-Equal $off.Reports[3] 'C9-66-00-00-00-00-00-00-00-00-00-00-00-00-00-00' 'LED init 2'
Assert-Equal $off.Reports[4] 'CB-03-1C-00-16-00-17-00-00-00-00-00-00-00-00-00' 'Known working off packet'

$color = & $scriptPath -Preview -Color '#123abc'
Assert-Equal $color.Color '#123ABC' 'Normalize hex input'
Assert-Equal $color.EffectiveColor '#123ABC' 'Full brightness preserves RGB'
Assert-Equal $color.Reports[4] 'CB-03-1C-12-16-3A-17-BC-00-00-00-00-00-00-00-00' 'RGB channel order'

$dim = & $scriptPath -Preview -Color '0080FF' -Brightness 50
Assert-Equal $dim.EffectiveColor '#004080' 'Half brightness including midpoint rounding'
$zero = & $scriptPath -Preview -Color 'FFFFFF' -Brightness 0
Assert-Equal $zero.Reports[4] $off.Reports[4] 'Zero brightness matches off'

foreach ($invalidColor in @('red', '#123', '1234567', 'GG0000', '000000;whoami')) {
    $rejected = $false
    try { & $scriptPath -Preview -Color $invalidColor | Out-Null }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Accepted invalid color: $invalidColor" }
}
foreach ($invalidBrightness in @(-1, 101)) {
    $rejected = $false
    try { & $scriptPath -Preview -Brightness $invalidBrightness | Out-Null }
    catch { $rejected = $true }
    if (-not $rejected) { throw "Accepted invalid brightness: $invalidBrightness" }
}

$rejected = $false
try { & $scriptPath -InstallStartup -Preview | Out-Null }
catch { $rejected = $true }
if (-not $rejected) { throw 'InstallStartup must not be combined with Preview.' }

Write-Output 'PASS: parsing, C# compilation, HID packets, RGB, brightness and parameter validation.'
