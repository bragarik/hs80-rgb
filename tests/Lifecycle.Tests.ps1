# SPDX-License-Identifier: GPL-3.0-or-later
# Real process/IPC tests with unique names. Never opens USB or stops a user's effect.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
    Write-Output 'SKIP: named-event process lifecycle tests require Windows.'
    return
}

$mainScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'hs80-rgb.ps1'
& $mainScript -Preview | Out-Null
$temp = Join-Path ([IO.Path]::GetTempPath()) ('hs80-ipc-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$children = New-Object 'Collections.Generic.List[Diagnostics.Process]'
$worker = Join-Path $temp 'worker.ps1'
@'
param([string]$MainScript, [string]$Name, [string]$Ready, [string]$Finished, [string]$Mode)
$ErrorActionPreference = 'Stop'
& $MainScript -Preview | Out-Null
$lease = [HS80Rgb.ControlLease]::Acquire($Name, 5000)
try {
    [IO.File]::WriteAllText($Ready, 'owned')
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt 20) {
        if ($Mode -eq 'Hold') { Start-Sleep -Milliseconds 50 }
        elseif ($lease.WaitForStop(50)) { break }
    }
} finally {
    # Marker precedes releasing ownership: a replacement must observe cleanup.
    [IO.File]::WriteAllText($Finished, 'cleaned')
    $lease.Dispose()
}
'@ | Set-Content -LiteralPath $worker -Encoding ASCII

function Start-TestOwner([string]$name, [string]$label, [string]$mode = 'Normal') {
    $ready = Join-Path $temp ($label + '.ready')
    $finished = Join-Path $temp ($label + '.finished')
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -MainScript "{1}" -Name "{2}" -Ready "{3}" -Finished "{4}" -Mode {5}' -f $worker, $mainScript, $name, $ready, $finished, $mode
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $child = [Diagnostics.Process]::Start($info)
    $children.Add($child)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $ready)) {
        if ($child.HasExited) { throw ('IPC worker failed: ' + $child.StandardError.ReadToEnd()) }
        if ($clock.Elapsed.TotalSeconds -gt 15) { throw 'IPC worker startup timed out.' }
        Start-Sleep -Milliseconds 30
    }
    return [pscustomobject]@{ Process = $child; Finished = $finished }
}

function Assert-WorkerExited($owner) {
    if (-not $owner.Process.WaitForExit(5000)) { throw 'Previous controller did not exit.' }
    if ($owner.Process.ExitCode -ne 0) { throw $owner.Process.StandardError.ReadToEnd() }
    if (-not (Test-Path -LiteralPath $owner.Finished)) { throw 'Previous controller skipped cleanup.' }
}

try {
    $name = 'Local\HS80Rgb.Tests.' + [Guid]::NewGuid().ToString('N')
    $owner = Start-TestOwner $name 'owner'
    $replacement = [HS80Rgb.ControlLease]::Acquire($name, 5000)
    try {
        if (-not (Test-Path -LiteralPath $owner.Finished)) { throw 'Replacement acquired ownership before cleanup.' }
        if ($replacement.StopRequested) { throw 'Replacement inherited a stale stop signal.' }
    } finally { $replacement.Dispose() }
    Assert-WorkerExited $owner

    # Two separate hidden processes replace each other, as startup/manual effects do.
    $first = Start-TestOwner $name 'first'
    $second = Start-TestOwner $name 'second'
    Assert-WorkerExited $first
    $stopper = [HS80Rgb.ControlLease]::Acquire($name, 5000)
    $stopper.Dispose()
    Assert-WorkerExited $second

    # A nonresponsive owner must prevent a second writer rather than overlap.
    $holder = Start-TestOwner $name 'holder' 'Hold'
    $timedOut = $false
    $unexpected = $null
    try { $unexpected = [HS80Rgb.ControlLease]::Acquire($name, 150) }
    catch {
        if ($_.Exception.ToString() -notmatch 'TimeoutException') { throw }
        $timedOut = $true
    } finally { if ($null -ne $unexpected) { $unexpected.Dispose() } }
    if (-not $timedOut) { throw 'A second writer was allowed while the first owner was unresponsive.' }
    $holder.Process.Kill()
    $holder.Process.WaitForExit()
    $recovered = [HS80Rgb.ControlLease]::Acquire($name, 5000)
    $recovered.Dispose()

    # Stop with no current owner is idempotent and does not require a USB device.
    $emptyStop = [HS80Rgb.ControlLease]::Acquire($name, 5000)
    $emptyStop.Dispose()
    Write-Output 'PASS: process replacement, graceful stop, cleanup ordering, timeout and crash recovery.'
} finally {
    foreach ($child in $children) {
        if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }
        $child.Dispose()
    }
    Remove-Item -LiteralPath $temp -Recurse -Force
}
