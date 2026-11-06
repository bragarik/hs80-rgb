# SPDX-License-Identifier: GPL-3.0-or-later
# Isolated startup/launcher test. Never touches the user's Startup folder or USB.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or $PSVersionTable.PSVersion.Major -ne 5) {
    Write-Output 'SKIP: GUI launcher compilation is tested on Windows PowerShell 5.1.'
    return
}
$mainScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'hs80-rgb.ps1'
. $mainScript -Version | Out-Null
$temp = Join-Path ([IO.Path]::GetTempPath()) ('hs80 startup test ' + [Guid]::NewGuid().ToString('N'))
$install = Join-Path $temp 'installed files'
$startupFolder = Join-Path $temp 'startup folder'
$fixture = Join-Path $temp 'fixture.ps1'
New-Item -ItemType Directory -Path $temp | Out-Null
@'
param([switch]$Startup, [string]$Color, [int]$Brightness, [string]$Effect, [int]$Period, [string]$Colors, [int]$Seed)
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class ConsoleProbe { [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); }'
$report = [pscustomobject]@{
    Startup = [bool]$Startup
    Color = $Color
    Brightness = $Brightness
    Effect = $Effect
    Period = $Period
    Colors = $Colors
    Seed = $Seed
    ProcessId = $PID
    ConsoleWindow = [ConsoleProbe]::GetConsoleWindow().ToInt64()
    MainWindow = [Diagnostics.Process]::GetCurrentProcess().MainWindowHandle.ToInt64()
}
$temporary = Join-Path $PSScriptRoot 'result.tmp'
[IO.File]::WriteAllText($temporary, ($report | ConvertTo-Json))
Move-Item -LiteralPath $temporary -Destination (Join-Path $PSScriptRoot 'result.json')
'@ | Set-Content -LiteralPath $fixture -Encoding ASCII

try {
    $parameters = '-Color 000000 -Brightness 30 -Effect Cycle -Period 12 -Colors AA00FF,0080FF,00FF80'
    $installed = Install-HS80Startup -ScriptPath $fixture -InstallDirectory $install -StartupDirectory $startupFolder -Parameters $parameters
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($installed.ShortcutPath)
    if ($shortcut.TargetPath -ne $installed.LauncherPath) { throw 'Shortcut does not point to the GUI launcher.' }
    if ($shortcut.Arguments -cne $parameters) { throw 'Startup parameters changed during installation.' }
    if ([IO.File]::ReadAllText($installed.ScriptPath) -cne [IO.File]::ReadAllText($fixture)) { throw 'Installed script differs from the source.' }

    # PE Optional Header Subsystem=2 is a GUI application; 3 would be a console.
    $bytes = [IO.File]::ReadAllBytes($installed.LauncherPath)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    $subsystem = [BitConverter]::ToUInt16($bytes, $peOffset + 24 + 68)
    if ($subsystem -ne 2) { throw 'Launcher was compiled as a console application.' }

    # Launch with the same executable/arguments stored in the .lnk. The fixture
    # reports whether the PowerShell child inherited or created any console.
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $shortcut.TargetPath
    $info.Arguments = $shortcut.Arguments
    $info.UseShellExecute = $false
    $child = [Diagnostics.Process]::Start($info)
    try {
        if (-not $child.WaitForExit(5000)) { throw 'GUI launcher stayed resident.' }
        if ($child.ExitCode -ne 0) { throw 'GUI launcher failed; inspect its startup.log.' }
    } finally { $child.Dispose() }
    $resultPath = Join-Path $install 'result.json'
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $resultPath)) {
        if ($clock.Elapsed.TotalSeconds -gt 20) { throw 'Hidden PowerShell did not finish the fixture.' }
        Start-Sleep -Milliseconds 50
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $fixtureProcess = Get-Process -Id $result.ProcessId -ErrorAction SilentlyContinue
    if ($null -ne $fixtureProcess) {
        try {
            if (-not $fixtureProcess.WaitForExit(5000)) { throw 'Fixture PowerShell did not exit.' }
        } finally { $fixtureProcess.Dispose() }
    }
    if (-not $result.Startup -or $result.ConsoleWindow -ne 0 -or $result.MainWindow -ne 0) {
        throw 'Startup PowerShell has a console/window, or lost its startup marker.'
    }
    if ($result.Effect -ne 'Cycle' -or $result.Colors -ne 'AA00FF,0080FF,00FF80' -or $result.Brightness -ne 30 -or $result.Period -ne 12) {
        throw 'Native command-line parsing changed palette/effect parameters.'
    }

    # Updating a saved preference reuses the launcher and rewrites the shortcut.
    $next = '-Color 000000 -Brightness 40 -Effect Random -Period 4 -Seed 42'
    $updated = Install-HS80Startup -ScriptPath $fixture -InstallDirectory $install -StartupDirectory $startupFolder -Parameters $next
    if ($updated.LauncherPath -ne $installed.LauncherPath) { throw 'Unchanged launcher was unnecessarily regenerated.' }
    $shortcut = $shell.CreateShortcut($updated.ShortcutPath)
    if ($shortcut.Arguments -cne $next) { throw 'Preference update did not refresh shortcut arguments.' }
    Write-Output 'PASS: GUI subsystem, isolated installation, hidden child with no console, palette arguments and preference update.'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
