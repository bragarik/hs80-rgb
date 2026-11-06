# SPDX-License-Identifier: GPL-3.0-or-later
# Verifies the distributable package, without publishing or requiring USB hardware.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ('hs80-package-test-' + [Guid]::NewGuid().ToString('N'))

try {
    $package = & (Join-Path $root 'scripts/Build-Release.ps1') -Version v0.2.0 -OutputDirectory $temp
    $hashLine = [IO.File]::ReadAllText($package.ChecksumPath).Trim()
    $expected = (Get-FileHash -LiteralPath $package.ZipPath -Algorithm SHA256).Hash.ToLowerInvariant() + '  hs80-rgb-v0.2.0.zip'
    if ($hashLine -cne $expected) { throw 'The published checksum does not match the ZIP.' }

    $extracted = Join-Path $temp 'extracted'
    Expand-Archive -LiteralPath $package.ZipPath -DestinationPath $extracted
    $packageRoot = Join-Path $extracted 'hs80-rgb'
    $expectedFiles = @('LICENSE', 'README.md', 'RELEASE-NOTES.md', 'hs80-rgb.bat', 'hs80-rgb.ps1', 'tests/Smoke.Tests.ps1', 'tests/Lifecycle.Tests.ps1', 'tests/Startup.Tests.ps1')
    $actualFiles = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse)
    if ($actualFiles.Count -ne $expectedFiles.Count) { throw 'The ZIP contains missing or unexpected files.' }
    foreach ($file in $expectedFiles) {
        $path = Join-Path $packageRoot $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing packaged file: $file" }
        if ($file -match '\.(bat|ps1)$') {
            if ([IO.File]::ReadAllText($path) -match '(?<!\r)\n') { throw "Non-Windows line endings: $file" }
        }
    }
    $packagedSource = [IO.File]::ReadAllText((Join-Path $packageRoot 'hs80-rgb.ps1')) -replace '\r\n', "`n"
    $originalSource = [IO.File]::ReadAllText((Join-Path $root 'hs80-rgb.ps1')) -replace '\r\n', "`n"
    if ($packagedSource -cne $originalSource) {
        throw 'The packaged controller differs from the source.'
    }

    # Exercise the extracted source as a user would, including its embedded C# compiler.
    & (Join-Path $packageRoot 'tests/Smoke.Tests.ps1')
    & (Join-Path $packageRoot 'tests/Lifecycle.Tests.ps1')
    & (Join-Path $packageRoot 'tests/Startup.Tests.ps1')
    Write-Output 'PASS: ZIP contents, CRLF scripts, checksum, source integrity and extracted controller.'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
