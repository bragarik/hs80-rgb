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
Assert-Equal $version 'HS80 RGB 0.2.0+startup.3' 'Version can be checked without accessing USB'

$off = & $scriptPath -Preview
Assert-Equal $off.Version '0.2.0+startup.3' 'Preview identifies the build'
Assert-Equal $off.Effect 'Static' 'The default remains one-shot static mode'
Assert-Equal $off.RunsContinuously $false 'The default does not leave a process running'
Assert-Equal $off.StartupParameters '-Color 000000 -Brightness 0 -Effect Static -Period 4' 'The startup preset records off at zero brightness'
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

$rainbow = & $scriptPath -Preview -Effect Rainbow
Assert-Equal $rainbow.RunsContinuously $true 'Rainbow is continuous'
Assert-Equal $rainbow.Brightness 100 'Rainbow is visible without a brightness argument'
Assert-Equal $rainbow.Period 10 'Rainbow defaults to a ten-second cycle'
Assert-Equal $rainbow.Samples.Count 4 'Animation preview includes quarter-cycle samples'
Assert-Equal $rainbow.EffectiveColor '#FF0000' 'Rainbow starts at red'
Assert-Equal $rainbow.StartupParameters '-Color 000000 -Brightness 100 -Effect Rainbow -Period 10' 'Startup saves the full animation parameters'

$breathe = & $scriptPath -Preview -Effect Breathe -Color AA00FF -Brightness 30 -Period 4
Assert-Equal $breathe.EffectiveColor '#000000' 'Breathe starts with the LEDs off'
Assert-Equal $breathe.Samples[2].Color '#33004D' 'Breathe peaks at the chosen color and brightness'
$whiteBreathe = & $scriptPath -Preview -Effect Breathe
Assert-Equal $whiteBreathe.Color '#FFFFFF' 'Breathe without a color defaults to white'
Assert-Equal $whiteBreathe.Brightness 100 'Default breathing is visible'
$blackBreathe = & $scriptPath -Preview -Effect Breathe -Color 000000
Assert-Equal $blackBreathe.Brightness 0 'Explicit black remains off in breathing mode'
$zeroAnimation = & $scriptPath -Preview -Effect Rainbow -Brightness 0
Assert-Equal $zeroAnimation.EffectiveColor '#000000' 'An explicit zero brightness is respected for animations'

function Frame-Hex([string]$effect, [double]$seconds) {
    $rgb = [HS80Rgb.Controller]::RenderFrame($effect, 170, 0, 255, 100, 6, $seconds)
    return [BitConverter]::ToString($rgb)
}
$wheel = @('FF-00-00', 'FF-FF-00', '00-FF-00', '00-FF-FF', '00-00-FF', 'FF-00-FF', 'FF-00-00')
for ($second = 0; $second -le 6; $second++) {
    Assert-Equal (Frame-Hex 'Rainbow' $second) $wheel[$second] 'Rainbow passes through the six hue sectors and wraps'
}
Assert-Equal (Frame-Hex 'Rainbow' 1.25) (Frame-Hex 'Rainbow' 13.25) 'Animation time wraps without accumulating drift'
Assert-Equal (Frame-Hex 'Breathe' 0) '00-00-00' 'Breathe minimum'
Assert-Equal (Frame-Hex 'Breathe' 3) 'AA-00-FF' 'Breathe maximum'
Assert-Equal (Frame-Hex 'Breathe' 6) '00-00-00' 'Breathe full cycle'
Assert-Equal ([BitConverter]::ToString([HS80Rgb.Controller]::BuildColorReport(18, 58, 188))) $color.Reports[4] 'Each animation frame uses only the known CB color packet'

$cycle = & $scriptPath -Preview -Effect Cycle -Colors '#FF0000, 0000ff' -Brightness 100 -Period 4
Assert-Equal $cycle.Colors 'FF0000,0000FF' 'Palette colors are normalized for shortcut arguments'
Assert-Equal $cycle.StartupParameters '-Color 000000 -Brightness 100 -Effect Cycle -Period 4 -Colors FF0000,0000FF' 'Startup preserves the complete palette'
Assert-Equal $cycle.Samples[0].Color '#FF0000' 'Cycle starts at the first color'
Assert-Equal $cycle.Samples[1].Color '#800080' 'Cycle blends between palette entries'
Assert-Equal $cycle.Samples[2].Color '#0000FF' 'Cycle reaches the next palette entry'
$cycleDefault = & $scriptPath -Preview -Effect Cycle
Assert-Equal $cycleDefault.Period 10 'Cycle defaults to a ten-second palette loop'
Assert-Equal $cycleDefault.Brightness 100 'A palette is visible without a brightness argument'
$paletteRenderer = New-Object HS80Rgb.EffectRenderer('Cycle', 0, 0, 0, 100, 4, 'FF0000,0000FF', 0)
Assert-Equal ([BitConverter]::ToString($paletteRenderer.Frame(4))) 'FF-00-00' 'The palette loop closes at the first color'

foreach ($name in @('Blink', 'Heartbeat')) {
    $singleColor = & $scriptPath -Preview -Effect $name
    Assert-Equal $singleColor.Color '#FFFFFF' 'Single-color effects default to visible white'
    Assert-Equal $singleColor.Period 2 'Blink and heartbeat default to two-second cycles'
    $blackEffect = & $scriptPath -Preview -Effect $name -Color 000000
    Assert-Equal $blackEffect.Brightness 0 'Explicit black is preserved'
}
Assert-Equal (Frame-Hex 'Blink' 0) 'AA-00-FF' 'Blink starts on'
Assert-Equal (Frame-Hex 'Blink' 2.999) 'AA-00-FF' 'Blink stays on for half the cycle'
Assert-Equal (Frame-Hex 'Blink' 3) '00-00-00' 'Blink switches off at the midpoint'
Assert-Equal (Frame-Hex 'Blink' 6) 'AA-00-FF' 'Blink restarts after a full cycle'
Assert-Equal (Frame-Hex 'Heartbeat' 0) '00-00-00' 'Heartbeat starts at rest'
Assert-Equal (Frame-Hex 'Heartbeat' 0.6) 'AA-00-FF' 'First heartbeat pulse reaches full brightness'
Assert-Equal (Frame-Hex 'Heartbeat' 2.1) '80-00-BF' 'Second heartbeat pulse is softer'
Assert-Equal (Frame-Hex 'Heartbeat' 3) '00-00-00' 'Heartbeat pauses after the two pulses'

$random = & $scriptPath -Preview -Effect Random -Seed 42 -Brightness 30
Assert-Equal $random.Seed 42 'An explicit random seed is preserved'
Assert-Equal $random.StartupParameters '-Color 000000 -Brightness 30 -Effect Random -Period 4 -Seed 42' 'Startup reproduces the selected random sequence'
$randomA = New-Object HS80Rgb.EffectRenderer('Random', 0, 0, 0, 100, 4, 'FF0000,0000FF', 42)
$randomB = New-Object HS80Rgb.EffectRenderer('Random', 0, 0, 0, 100, 4, 'FF0000,0000FF', 43)
$savedRandomFrame = [BitConverter]::ToString($randomA.Frame(1.5))
$randomA.Frame(1000) | Out-Null
Assert-Equal ([BitConverter]::ToString($randomA.Frame(1.5))) $savedRandomFrame 'Random frames are independent of call order'
if ([BitConverter]::ToString($randomA.Frame(0)) -eq [BitConverter]::ToString($randomB.Frame(0))) {
    throw 'Different seeds unexpectedly produced the same test sequence.'
}
$beforeBoundary = $randomA.Frame(3.999999)
$atBoundary = $randomA.Frame(4)
for ($channel = 0; $channel -lt 3; $channel++) {
    if ([Math]::Abs([int]$beforeBoundary[$channel] - [int]$atBoundary[$channel]) -gt 1) {
        throw 'Random transitions jump at a segment boundary.'
    }
}
foreach ($name in @('Cycle', 'Blink', 'Heartbeat', 'Random')) {
    $zeroEffect = & $scriptPath -Preview -Effect $name -Brightness 0
    Assert-Equal $zeroEffect.EffectiveColor '#000000' 'Zero brightness disables every effect output'
}

foreach ($badArguments in @(
    @{ Effect = 'Unknown'; Preview = $true },
    @{ Effect = 'Rainbow'; Period = 0; Preview = $true },
    @{ Effect = 'Breathe'; Period = 3601; Preview = $true },
    @{ Effect = 'Cycle'; Colors = 'FF0000'; Preview = $true },
    @{ Effect = 'Cycle'; Colors = 'FF0000,GG0000'; Preview = $true },
    @{ Effect = 'Cycle'; Colors = ('FF0000,' * 16 + '0000FF'); Preview = $true },
    @{ Effect = 'Random'; Seed = -1; Preview = $true },
    @{ Stop = $true; Color = 'FFFFFF' },
    @{ Stop = $true; InstallStartup = $true }
)) {
    $rejected = $false
    try { & $scriptPath @badArguments | Out-Null }
    catch { $rejected = $true }
    if (-not $rejected) { throw 'Accepted an invalid effect, period or stop combination.' }
}

foreach ($badArguments in @(
    @{ Effect = 'Breathe'; Colors = 'FF0000,0000FF'; Preview = $true },
    @{ Effect = 'Cycle'; Seed = 42; Preview = $true }
)) {
    & $scriptPath @badArguments 2>$null | Out-Null
    if ($LASTEXITCODE -ne 1) { throw 'An option for the wrong effect was silently accepted.' }
}
# The two nonzero script exits above are expected and asserted. Do not leak
# their exit status to the GitHub Actions shell wrapper after a passing suite.
$global:LASTEXITCODE = 0

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

Write-Output 'PASS: compilation, HID packets, defaults, animation frames, startup parameters and HID collection selection.'
