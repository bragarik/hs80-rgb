# SPDX-License-Identifier: GPL-3.0-or-later
# Protocol reference: OpenLinkHub, src/devices/hs80rgb/hs80rgb.go
# Requires Windows PowerShell 5.1 or newer. Preview also works on other platforms.
[CmdletBinding(DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Apply')]
    [Parameter(ParameterSetName = 'Install')]
    [ValidatePattern('^#?[0-9a-fA-F]{6}$')]
    [string]$Color = '000000',

    [Parameter(ParameterSetName = 'Apply')]
    [Parameter(ParameterSetName = 'Install')]
    [ValidateRange(0, 100)]
    [int]$Brightness = 100,

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$Preview,

    [Parameter(Mandatory, ParameterSetName = 'List')]
    [switch]$ListDevices,

    [Parameter(Mandatory, ParameterSetName = 'Install')]
    [switch]$InstallStartup,

    [Parameter(Mandatory, ParameterSetName = 'Uninstall')]
    [switch]$UninstallStartup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $isWindowsPlatform = [Environment]::OSVersion.Platform -eq 'Win32NT'
    if (-not $isWindowsPlatform -and -not $Preview) {
        throw 'O controle USB e a inicializacao automatica exigem Windows.'
    }

    # Accept only a validated hex color and numeric brightness in shortcut arguments.
    $hexColor = $Color.TrimStart('#').ToUpperInvariant()

    if ($InstallStartup -or $UninstallStartup) {
        $startup = [Environment]::GetFolderPath('Startup')
        $shortcutPath = Join-Path $startup 'HS80 RGB.lnk'

        if ($UninstallStartup) {
            if (Test-Path -LiteralPath $shortcutPath) {
                Remove-Item -LiteralPath $shortcutPath
            }
            Write-Output 'Inicializacao automatica removida. Nenhum processo permanente foi instalado.'
            return
        }

        $installDir = Join-Path $env:LOCALAPPDATA 'HS80-RGB'
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        $installedScript = Join-Path $installDir 'hs80-rgb.ps1'
        if ([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath($installedScript)) {
            Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
        }

        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shortcut.Arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Color {1} -Brightness {2}' -f $installedScript, $hexColor, $Brightness
        $shortcut.WorkingDirectory = $installDir
        $shortcut.Save()
        Write-Output ('Inicializacao configurada: #{0}, brilho {1}%. A cor sera aplicada no proximo login.' -f $hexColor, $Brightness)
        return
    }

    if (-not ('HS80Rgb.Controller' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace HS80Rgb
{
    public static class Controller
    {
        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
        static extern uint CM_Get_Device_Interface_List_SizeW(
            out uint size, ref Guid guid, string device, uint flags);

        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
        static extern uint CM_Get_Device_Interface_ListW(
            ref Guid guid, string device, [Out] char[] buffer, uint size, uint flags);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern SafeFileHandle CreateFileW(string path, uint access,
            uint share, IntPtr security, uint creation, uint flags, IntPtr template);

        [DllImport("hid.dll")]
        static extern bool HidD_GetPreparsedData(SafeFileHandle handle, out IntPtr data);

        [DllImport("hid.dll")]
        static extern bool HidD_FreePreparsedData(IntPtr data);

        [DllImport("hid.dll")]
        static extern int HidP_GetCaps(IntPtr data, [Out] byte[] caps);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool WriteFile(SafeFileHandle handle, byte[] buffer,
            uint length, out uint written, IntPtr overlapped);

        static string[] GetPaths()
        {
            Guid guid = new Guid("4D1E55B2-F16F-11CF-88CB-001111000030");
            // Devices may change between the size query and the list query.
            for (int attempt = 0; attempt < 3; attempt++)
            {
                uint size;
                uint status = CM_Get_Device_Interface_List_SizeW(out size, ref guid, null, 0);
                if (status != 0)
                    throw new Exception("HID enumeration failed: CONFIGRET " + status);
                char[] buffer = new char[size];
                status = CM_Get_Device_Interface_ListW(ref guid, null, buffer, size, 0);
                if (status == 0x1A) continue; // CR_BUFFER_SMALL
                if (status != 0)
                    throw new Exception("HID list failed: CONFIGRET " + status);

                List<string> paths = new List<string>();
                foreach (string path in new string(buffer).Split('\0'))
                    if (path.IndexOf("vid_1b1c&pid_0a88",
                            StringComparison.OrdinalIgnoreCase) >= 0)
                        paths.Add(path);
                return paths.ToArray();
            }
            throw new Exception("USB devices changed during enumeration. Try again.");
        }

        static int OutputLength(string path)
        {
            using (SafeFileHandle handle = CreateFileW(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero))
            {
                if (handle.IsInvalid) return -1;
                IntPtr data;
                if (!HidD_GetPreparsedData(handle, out data)) return -1;
                try
                {
                    byte[] caps = new byte[64];
                    if (HidP_GetCaps(data, caps) != 0x00110000) return -1;
                    return BitConverter.ToUInt16(caps, 6);
                }
                finally { HidD_FreePreparsedData(data); }
            }
        }

        public static string[] ListDevices()
        {
            List<string> result = new List<string>();
            foreach (string path in GetPaths())
                result.Add(path + " | OutputReportByteLength=" + OutputLength(path));
            return result.ToArray();
        }

        public static byte[][] BuildReports(byte red, byte green, byte blue)
        {
            byte[][] commands = new byte[][] {
                new byte[] { 0xC8, 0x00 },
                new byte[] { 0xC8, 0x01 },
                new byte[] { 0xC9, 0x64 },
                new byte[] { 0xC9, 0x66 },
                new byte[] { 0xCB, 0x03, 0x1C, red, 0x16, green, 0x17, blue }
            };
            byte[][] reports = new byte[commands.Length][];
            for (int i = 0; i < commands.Length; i++)
            {
                reports[i] = new byte[16];
                Array.Copy(commands[i], reports[i], commands[i].Length);
            }
            return reports;
        }

        public static void Apply(byte red, byte green, byte blue)
        {
            List<string> candidates = new List<string>();
            foreach (string path in GetPaths())
                if (OutputLength(path) == 16) candidates.Add(path);

            if (candidates.Count == 0)
                throw new Exception("HS80 USB 1B1C:0A88 control interface not found or inaccessible. Close iCUE and check the USB connection.");
            if (candidates.Count != 1)
                throw new Exception("More than one compatible interface found. Connect only one HS80 and run -ListDevices.");

            using (SafeFileHandle handle = CreateFileW(
                candidates[0], 0x40000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero))
            {
                if (handle.IsInvalid)
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                foreach (byte[] report in BuildReports(red, green, blue))
                {
                    uint written;
                    if (!WriteFile(handle, report, 16, out written, IntPtr.Zero))
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                    if (written != 16)
                        throw new Exception("Incomplete HID write; reconnect the headset and try again.");
                    System.Threading.Thread.Sleep(30);
                }
            }
            // Do not restore hardware mode: retain the requested color after exit.
        }
    }
}
'@
    }

    if ($ListDevices) {
        $devices = @([HS80Rgb.Controller]::ListDevices())
        if ($devices.Count -eq 0) {
            Write-Output 'Nenhuma interface HID do HS80 USB 1B1C:0A88 encontrada.'
        } else {
            $devices | Write-Output
        }
        return
    }

    # Software brightness: scale RGB channels; do not modify hardware settings.
    $channels = @(for ($i = 0; $i -lt 6; $i += 2) {
        [byte][Math]::Round(
            [Convert]::ToInt32($hexColor.Substring($i, 2), 16) * $Brightness / 100.0,
            [MidpointRounding]::AwayFromZero)
    })

    if ($Preview) {
        [pscustomobject]@{
            Color = '#' + $hexColor
            Brightness = $Brightness
            EffectiveColor = '#{0:X2}{1:X2}{2:X2}' -f $channels[0], $channels[1], $channels[2]
            Reports = @([HS80Rgb.Controller]::BuildReports($channels[0], $channels[1], $channels[2]) | ForEach-Object {
                [BitConverter]::ToString($_)
            })
        }
        return
    }

    [HS80Rgb.Controller]::Apply($channels[0], $channels[1], $channels[2])
    Write-Output ('Comandos enviados: #{0}, brilho {1}%. Conexao encerrada.' -f $hexColor, $Brightness)
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
