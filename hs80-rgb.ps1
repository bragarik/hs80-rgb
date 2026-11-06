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
    [int]$Brightness = 0,

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$Preview,

    [Parameter(Mandatory, ParameterSetName = 'List')]
    [switch]$ListDevices,

    [Parameter(Mandatory, ParameterSetName = 'Install')]
    [switch]$InstallStartup,

    [Parameter(Mandatory, ParameterSetName = 'Uninstall')]
    [switch]$UninstallStartup,

    [Parameter(Mandatory, ParameterSetName = 'Version')]
    [switch]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$programVersion = '0.1.0+rev.4'

if ($Version) {
    Write-Output ('HS80 RGB ' + $programVersion)
    return
}

try {
    $isWindowsPlatform = [Environment]::OSVersion.Platform -eq 'Win32NT'
    if (-not $isWindowsPlatform -and -not $Preview) {
        throw 'O controle USB e a inicializacao automatica exigem Windows.'
    }

    # Accept only a validated hex color and numeric brightness in shortcut arguments.
    $hexColor = $Color.TrimStart('#').ToUpperInvariant()
    # The default off preset reports 0%. A requested nonblack color remains
    # visible without an extra brightness argument. Honor every explicit value.
    if (-not $PSBoundParameters.ContainsKey('Brightness') -and $hexColor -ne '000000') {
        $Brightness = 100
    }

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
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace HS80Rgb
{
    public sealed class HidInterfaceInfo
    {
        public string Path;
        public int OutputReportByteLength = -1;
        public ushort UsagePage;
        public ushort Usage;
        public byte[] SupportedRgbReports = new byte[0];
    }

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

        [DllImport("hid.dll")]
        static extern int HidP_InitializeReportForID(int reportType, byte reportId,
            IntPtr data, [Out] byte[] report, uint reportLength);

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

        static HidInterfaceInfo Inspect(string path)
        {
            HidInterfaceInfo info = new HidInterfaceInfo();
            info.Path = path;
            using (SafeFileHandle handle = CreateFileW(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero))
            {
                if (handle.IsInvalid) return info;
                IntPtr data;
                if (!HidD_GetPreparsedData(handle, out data)) return info;
                try
                {
                    byte[] caps = new byte[64];
                    if (HidP_GetCaps(data, caps) != 0x00110000) return info;
                    info.Usage = BitConverter.ToUInt16(caps, 0);
                    info.UsagePage = BitConverter.ToUInt16(caps, 2);
                    info.OutputReportByteLength = BitConverter.ToUInt16(caps, 6);
                    if (info.OutputReportByteLength == 16)
                    {
                        List<byte> supported = new List<byte>();
                        foreach (byte id in new byte[] { 0xC8, 0xC9, 0xCB })
                        {
                            // This HID parser call only initializes a memory buffer.
                            // It does not send any data to the headset.
                            if (HidP_InitializeReportForID(1, id, data, new byte[16], 16)
                                    == 0x00110000)
                                supported.Add(id);
                        }
                        info.SupportedRgbReports = supported.ToArray();
                    }
                    return info;
                }
                finally { HidD_FreePreparsedData(data); }
            }
        }

        // Windows exposes separate top-level collections (Col01, Col02, ...)
        // for one USB interface. Equal report lengths do not make them equivalent.
        public static string SelectControlInterface(HidInterfaceInfo[] interfaces)
        {
            List<string> candidates = new List<string>();
            foreach (HidInterfaceInfo info in interfaces)
            {
                if (info == null || info.Path == null) continue;
                string[] parts = info.Path.Split('#');
                if (parts.Length < 3 || !Regex.IsMatch(parts[1],
                        @"^vid_1b1c&pid_0a88&mi_03(?:&col[0-9a-f]{2})?$",
                        RegexOptions.IgnoreCase)) continue;
                if (info.OutputReportByteLength != 16) continue;
                if (info.UsagePage != 0xFFC5 || info.Usage != 0x0001) continue;
                if (info.SupportedRgbReports == null) continue;
                // Observed Windows descriptor: vendor page FFC5, usage 1, C8 only.
                // C9 and CB belong to the working command sequence but are not
                // advertised by this descriptor; requiring them rejects the device.
                if (Array.IndexOf(info.SupportedRgbReports, (byte)0xC8) < 0) continue;
                if (!candidates.Contains(info.Path)) candidates.Add(info.Path);
            }

            if (candidates.Count == 0)
                throw new Exception("No HS80 USB 1B1C:0A88 MI_03 control collection found (UsagePage FFC5, Usage 1, 16 bytes, report C8). Close iCUE and run -ListDevices.");
            if (candidates.Count != 1)
                throw new Exception("Multiple HS80 RGB control collections found on UsagePage FFC5. Connect only one HS80 and share the output of -ListDevices.");
            return candidates[0];
        }

        public static string[] ListDevices()
        {
            List<string> result = new List<string>();
            foreach (string path in GetPaths())
            {
                HidInterfaceInfo info = Inspect(path);
                string reports = info.SupportedRgbReports.Length == 0 ? "none" :
                    BitConverter.ToString(info.SupportedRgbReports).Replace('-', ',');
                result.Add(String.Format(
                    "{0} | OutputReportByteLength={1} | UsagePage=0x{2:X4} | Usage=0x{3:X4} | RgbReports={4}",
                    path, info.OutputReportByteLength, info.UsagePage, info.Usage, reports));
            }
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
            List<HidInterfaceInfo> interfaces = new List<HidInterfaceInfo>();
            foreach (string path in GetPaths())
                interfaces.Add(Inspect(path));
            string selectedPath = SelectControlInterface(interfaces.ToArray());

            using (SafeFileHandle handle = CreateFileW(
                selectedPath, 0x40000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero))
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
            Version = $programVersion
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
