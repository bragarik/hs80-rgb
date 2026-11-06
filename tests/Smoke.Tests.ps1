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

$version = & $scriptPath -Version
Assert-Equal $version 'HS80 RGB 0.1.0+rev.4' 'Version can be checked without accessing USB'

$off = & $scriptPath -Preview
Assert-Equal $off.Version '0.1.0+rev.4' 'Preview identifies the build'
Assert-Equal $off.Brightness 0 'Default off preset stores and reports zero brightness'
Assert-Equal $off.EffectiveColor '#000000' 'Default is off'
Assert-Equal $off.Reports.Count 5 'Five HID reports'
Assert-Equal $off.Reports[0] 'C8-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00' 'Mode reset'
Assert-Equal $off.Reports[1] 'C8-01-00-00-00-00-00-00-00-00-00-00-00-00-00-00' 'Software mode'
Assert-Equal $off.Reports[2] 'C9-64-00-00-00-00-00-00-00-00-00-00-00-00-00-00' 'LED init 1'
Assert-Equal $off.Reports[3] 'C9-66-00-00-00-00-00-00-00-00-00-00-00-00-00-00' 'LED init 2'
Assert-Equal $off.Reports[4] 'CB-03-1C-00-16-00-17-00-00-00-00-00-00-00-00-00' 'Known working off packet'

$color = & $scriptPath -Preview -Color '#123abc'
Assert-Equal $color.Color '#123ABC' 'Normalize hex input'
Assert-Equal $color.Brightness 100 'A requested color remains visible without a brightness argument'
Assert-Equal $color.EffectiveColor '#123ABC' 'Full brightness preserves RGB'
Assert-Equal $color.Reports[4] 'CB-03-1C-12-16-3A-17-BC-00-00-00-00-00-00-00-00' 'RGB channel order'

$dim = & $scriptPath -Preview -Color '0080FF' -Brightness 50
Assert-Equal $dim.EffectiveColor '#004080' 'Half brightness including midpoint rounding'
$zero = & $scriptPath -Preview -Color 'FFFFFF' -Brightness 0
Assert-Equal $zero.Brightness 0 'An explicit zero is not replaced by the visible-color default'
Assert-Equal $zero.Reports[4] $off.Reports[4] 'Zero brightness matches off'

$explicitBlack = & $scriptPath -Preview -Color '#000000'
Assert-Equal $explicitBlack.Brightness 0 'Explicit black uses the off preset'
$explicitBrightness = & $scriptPath -Preview -Brightness 25
Assert-Equal $explicitBrightness.Brightness 25 'An explicit brightness is preserved even with default black'

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

# Regression: one physical HS80 exposes two collections of equal output length.
# Uses the capability values reported by the user on Windows 11. Paths are anonymized.
function New-Interface([string]$path, [int]$length, [byte[]]$reports, [uint16]$usagePage = 0xFFC5, [uint16]$usage = 1) {
    $info = New-Object HS80Rgb.HidInterfaceInfo
    $info.Path = $path
    $info.OutputReportByteLength = $length
    $info.SupportedRgbReports = $reports
    $info.UsagePage = $usagePage
    $info.Usage = $usage
    return $info
}

$path1 = '\\?\HID#VID_1B1C&PID_0A88&MI_03&Col01#a&unit1&0&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}'
$path2 = '\\?\HID#VID_1B1C&PID_0A88&MI_03&Col02#a&unit1&0&0001#{4d1e55b2-f16f-11cf-88cb-001111000030}'
$nonRgb = New-Interface $path1 16 @() 0x000C
$rgb = New-Interface $path2 16 @(0xC8)
Assert-Equal ([HS80Rgb.Controller]::SelectControlInterface(@($nonRgb, $rgb))) $path2 'Observed FFC5 collection with only C8 is accepted'
Assert-Equal ([HS80Rgb.Controller]::SelectControlInterface(@($rgb, $nonRgb))) $path2 'Selection does not depend on enumeration order'

# Collection numbering itself must not determine selection.
$rgb1 = New-Interface $path1 16 @(0xC8)
$nonRgb2 = New-Interface $path2 16 @() 0x000C
Assert-Equal ([HS80Rgb.Controller]::SelectControlInterface(@($rgb1, $nonRgb2))) $path1 'Collection names are not hardcoded'

$otherDevice = New-Interface ($path2.Replace('PID_0A88', 'PID_0A97')) 16 @(0xC8, 0xC9, 0xCB)
$otherInterface = New-Interface ($path2.Replace('MI_03', 'MI_02')) 16 @(0xC8, 0xC9, 0xCB)
Assert-Equal ([HS80Rgb.Controller]::SelectControlInterface(@($otherDevice, $otherInterface, $rgb))) $path2 'Wrong model and interface are excluded'

$secondHeadset = New-Interface ($path2.Replace('unit1', 'unit2')) 16 @(0xC8, 0xC9, 0xCB)
foreach ($ambiguous in @(@($rgb, $secondHeadset), @($rgb, $rgb1))) {
    $rejected = $false
    try { [HS80Rgb.Controller]::SelectControlInterface($ambiguous) | Out-Null }
    catch { $rejected = $true }
    if (-not $rejected) { throw 'Ambiguous RGB collections must not receive commands.' }
}

$missingC8 = New-Interface $path2 16 @(0xC9, 0xCB)
$wrongPage = New-Interface $path1 16 @(0xC8, 0xC9, 0xCB) 0x000C
$wrongUsage = New-Interface $path2 16 @(0xC8) 0xFFC5 2
$wrongLength = New-Interface $path2 64 @(0xC8, 0xC9, 0xCB)
Assert-Equal ([HS80Rgb.Controller]::SelectControlInterface(@($wrongPage, $rgb))) $path2 'Consumer collection is excluded even if reports overlap'
foreach ($invalid in @($nonRgb, $missingC8, $wrongPage, $wrongUsage, $wrongLength, $otherDevice, $otherInterface)) {
    $rejected = $false
    try { [HS80Rgb.Controller]::SelectControlInterface(@($invalid)) | Out-Null }
    catch { $rejected = $true }
    if (-not $rejected) { throw 'An incompatible interface was accepted.' }
}

Write-Output 'PASS: compilation, HID packets, RGB, brightness, parameters and HID collection selection.'
