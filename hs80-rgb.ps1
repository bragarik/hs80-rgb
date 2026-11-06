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
    [Parameter(ParameterSetName = 'Install')]
    [ValidateSet('Static', 'Rainbow', 'Breathe', 'Cycle', 'Blink', 'Heartbeat', 'Random')]
    [string]$Effect = 'Static',

    [Parameter(ParameterSetName = 'Apply')]
    [Parameter(ParameterSetName = 'Install')]
    [ValidatePattern('^\s*#?[0-9a-fA-F]{6}(?:\s*,\s*#?[0-9a-fA-F]{6}){1,15}\s*$')]
    [string]$Colors = 'FF0000,00FF00,0000FF',

    [Parameter(ParameterSetName = 'Apply')]
    [Parameter(ParameterSetName = 'Install')]
    [ValidateRange(0, 2147483647)]
    [int]$Seed = 0,

    [Parameter(ParameterSetName = 'Apply')]
    [Parameter(ParameterSetName = 'Install')]
    [ValidateRange(1, 3600)]
    [int]$Period = 4,

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$Preview,

    [Parameter(ParameterSetName = 'Apply')]
    [switch]$Startup,

    [Parameter(Mandatory, ParameterSetName = 'List')]
    [switch]$ListDevices,

    [Parameter(Mandatory, ParameterSetName = 'Stop')]
    [switch]$Stop,

    [Parameter(Mandatory, ParameterSetName = 'Install')]
    [switch]$InstallStartup,

    [Parameter(Mandatory, ParameterSetName = 'Uninstall')]
    [switch]$UninstallStartup,

    [Parameter(Mandatory, ParameterSetName = 'Version')]
    [switch]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$programVersion = '0.2.0+startup.3'

function Get-HS80StartupLauncherSource {
    return @'
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Collections.Generic;

// GUI-subsystem entry point: it has no console of its own. Unlike a console
// shortcut with WindowStyle Hidden, the child is created without a window.
public static class HS80StartupLauncher
{
    static string Quote(string value)
    {
        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') result.Append('\\', slashes * 2 + 1);
            else result.Append('\\', slashes);
            result.Append(c);
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        return result.Append('"').ToString();
    }

    [STAThread]
    public static int Main(string[] args)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string log = Path.Combine(root, "startup.log");
        try
        {
            // Bound the diagnostic file. No effect frames or personal data are logged.
            try
            {
                if (File.Exists(log) && new FileInfo(log).Length > 262144) File.WriteAllText(log, "");
                File.AppendAllText(log, DateTime.UtcNow.ToString("o") + " launcher: starting hidden PowerShell\r\n");
            }
            catch { } // Diagnostic I/O must not prevent the controller from starting.
            List<string> arguments = new List<string>();
            foreach (string value in args) arguments.Add(Quote(value));
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");
            info.Arguments = "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " +
                Quote(Path.Combine(root, "hs80-rgb.ps1")) + " -Startup " + String.Join(" ", arguments.ToArray());
            info.WorkingDirectory = root;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.WindowStyle = ProcessWindowStyle.Hidden;
            using (Process child = Process.Start(info))
            {
                if (child == null) throw new InvalidOperationException("PowerShell was not started.");
            }
            // Do not wait: animations leave only the PowerShell controller running.
            return 0;
        }
        catch (Exception error)
        {
            try { File.AppendAllText(log, DateTime.UtcNow.ToString("o") + " launcher error: " + error.Message + "\r\n"); }
            catch { }
            return 1;
        }
    }
}
'@
}

function Install-HS80Startup {
    param([string]$ScriptPath, [string]$InstallDirectory, [string]$StartupDirectory, [string]$Parameters)
    if ($PSVersionTable.PSVersion.Major -ne 5) {
        throw 'Para configurar a inicializacao, use hs80-rgb.bat (Windows PowerShell 5.1).'
    }
    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $StartupDirectory -Force | Out-Null
    $installedScript = Join-Path $InstallDirectory 'hs80-rgb.ps1'
    if ([IO.Path]::GetFullPath($ScriptPath) -ne [IO.Path]::GetFullPath($installedScript)) {
        Copy-Item -LiteralPath $ScriptPath -Destination $installedScript -Force
    }
    $source = Get-HS80StartupLauncherSource
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $id = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($source -replace '\r\n', "`n")))).Replace('-', '').Substring(0, 16)
    } finally { $sha.Dispose() }
    $launcher = Join-Path $InstallDirectory ('HS80Rgb.Startup-' + $id + '.exe')
    if (-not (Test-Path -LiteralPath $launcher)) {
        Add-Type -TypeDefinition $source -OutputAssembly $launcher -OutputType WindowsApplication
    }
    $shortcutPath = Join-Path $StartupDirectory 'HS80 RGB.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $launcher
    $shortcut.Arguments = $Parameters
    $shortcut.WorkingDirectory = $InstallDirectory
    $shortcut.Save()
    return [pscustomobject]@{ ScriptPath = $installedScript; LauncherPath = $launcher; ShortcutPath = $shortcutPath }
}

$startupLogPath = $null
$startupClock = [Diagnostics.Stopwatch]::StartNew()
function Write-HS80StartupLog([string]$Message) {
    if ($null -eq $startupLogPath) { return }
    try {
        $line = '{0:o} +{1:F3}s {2}' -f [DateTime]::UtcNow, $startupClock.Elapsed.TotalSeconds, $Message
        [IO.File]::AppendAllText($startupLogPath, $line + "`r`n")
    } catch { }
}

if ($Version) {
    Write-Output ('HS80 RGB ' + $programVersion)
    return
}

try {
    $isWindowsPlatform = [Environment]::OSVersion.Platform -eq 'Win32NT'
    if (-not $isWindowsPlatform -and -not $Preview) {
        throw 'O controle USB e a inicializacao automatica exigem Windows.'
    }
    if ($Startup -and -not $Preview) {
        $startupLogPath = Join-Path $PSScriptRoot 'startup.log'
        Write-HS80StartupLog ('script started; version=' + $programVersion)
    }

    # Accept only a validated hex color and numeric brightness in shortcut arguments.
    $hexColor = $Color.TrimStart('#').ToUpperInvariant()
    $isAnimation = $Effect -ne 'Static'
    if ($Effect -in @('Breathe', 'Blink', 'Heartbeat') -and -not $PSBoundParameters.ContainsKey('Color')) {
        $hexColor = 'FFFFFF'
    }
    if (-not $PSBoundParameters.ContainsKey('Period')) {
        if ($Effect -in @('Rainbow', 'Cycle')) { $Period = 10 }
        elseif ($Effect -in @('Blink', 'Heartbeat')) { $Period = 2 }
    }
    if ($PSBoundParameters.ContainsKey('Colors') -and $Effect -ne 'Cycle') {
        throw '-Colors exige -Effect Cycle.'
    }
    if ($PSBoundParameters.ContainsKey('Seed') -and $Effect -ne 'Random') {
        throw '-Seed exige -Effect Random.'
    }
    $palette = (($Colors -split ',' | ForEach-Object { $_.Trim().TrimStart('#').ToUpperInvariant() }) -join ',')
    if ($Effect -eq 'Random' -and -not $PSBoundParameters.ContainsKey('Seed')) {
        $Seed = Get-Random -Minimum 0 -Maximum 2147483647
    }
    # The default off preset reports 0%. A requested nonblack color remains
    # visible without an extra brightness argument. Honor every explicit value.
    if (-not $PSBoundParameters.ContainsKey('Brightness') -and ($hexColor -ne '000000' -or $Effect -in @('Rainbow', 'Cycle', 'Random'))) {
        $Brightness = 100
    }
    $startupParameters = '-Color {0} -Brightness {1} -Effect {2} -Period {3}' -f $hexColor, $Brightness, $Effect, $Period
    if ($Effect -eq 'Cycle') { $startupParameters += ' -Colors ' + $palette }
    if ($Effect -eq 'Random') { $startupParameters += ' -Seed ' + $Seed }

    if ($InstallStartup -or $UninstallStartup) {
        $startupDirectory = [Environment]::GetFolderPath('Startup')
        $shortcutPath = Join-Path $startupDirectory 'HS80 RGB.lnk'

        if ($UninstallStartup) {
            if (Test-Path -LiteralPath $shortcutPath) {
                Remove-Item -LiteralPath $shortcutPath
            }
            Write-Output 'Inicializacao automatica removida. Para parar uma animacao ativa, use -Stop.'
            return
        }

        $installDir = Join-Path $env:LOCALAPPDATA 'HS80-RGB'
        Install-HS80Startup -ScriptPath $PSCommandPath -InstallDirectory $installDir -StartupDirectory $startupDirectory -Parameters $startupParameters | Out-Null
        if ($isAnimation) {
            Write-Output ('Inicializacao configurada: {0}, brilho {1}%, periodo {2}s. Sera aplicada no proximo login.' -f $Effect, $Brightness, $Period)
        } else {
            Write-Output ('Inicializacao configurada: #{0}, brilho {1}%. Sera aplicada no proximo login.' -f $hexColor, $Brightness)
        }
        return
    }

    if (-not ('HS80Rgb.Controller' -as [type])) {
        Write-HS80StartupLog 'controller compilation started'
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Diagnostics;
using Microsoft.Win32.SafeHandles;

namespace HS80Rgb
{
    // One controller per Windows session, shared by all copies of the script.
    // A new owner requests a graceful stop, waits for cleanup, then takes over.
    public sealed class ControlLease : IDisposable
    {
        public const string DefaultName = @"Local\HS80Rgb.Control.v02";
        readonly Mutex mutex;
        readonly EventWaitHandle stop;
        bool disposed;

        ControlLease(Mutex mutex, EventWaitHandle stop)
        {
            this.mutex = mutex;
            this.stop = stop;
        }

        public static ControlLease AcquireDefault()
        {
            return Acquire(DefaultName, 5000);
        }

        public static ControlLease Acquire(string name, int timeoutMilliseconds)
        {
            if (String.IsNullOrEmpty(name)) throw new ArgumentException("Missing control name.");
            if (timeoutMilliseconds < 1) throw new ArgumentOutOfRangeException("timeoutMilliseconds");
            Mutex mutex = new Mutex(false, name + ".Mutex");
            EventWaitHandle stop = null;
            bool acquired = false;
            try
            {
                stop = new EventWaitHandle(false, EventResetMode.ManualReset, name + ".Stop");
                Stopwatch clock = Stopwatch.StartNew();
                do
                {
                    // Repeat the signal so concurrent replacements cannot lose it
                    // when an intermediate owner resets the event after takeover.
                    stop.Set();
                    try { acquired = mutex.WaitOne(50); }
                    catch (AbandonedMutexException) { acquired = true; }
                    if (acquired)
                    {
                        stop.Reset();
                        return new ControlLease(mutex, stop);
                    }
                } while (clock.ElapsedMilliseconds < timeoutMilliseconds);
                throw new TimeoutException("The previous HS80 controller did not stop within the timeout. No new USB commands were sent.");
            }
            catch
            {
                if (acquired) mutex.ReleaseMutex();
                if (stop != null) stop.Dispose();
                mutex.Dispose();
                throw;
            }
        }

        public bool StopRequested { get { return stop.WaitOne(0); } }
        public bool WaitForStop(int milliseconds) { return stop.WaitOne(milliseconds); }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            try { mutex.ReleaseMutex(); }
            finally { stop.Dispose(); mutex.Dispose(); }
        }
    }

    public sealed class DeviceConnection : IDisposable
    {
        readonly SafeFileHandle handle;
        readonly bool clearOnDispose;
        bool disposed;

        internal DeviceConnection(SafeFileHandle handle, bool clearOnDispose)
        {
            this.handle = handle;
            this.clearOnDispose = clearOnDispose;
        }

        public void WriteColor(byte red, byte green, byte blue)
        {
            if (disposed) throw new ObjectDisposedException("DeviceConnection");
            Controller.WriteReport(handle, Controller.BuildColorReport(red, green, blue));
        }

        public void Dispose()
        {
            if (disposed) return;
            try
            {
                if (clearOnDispose)
                {
                    // Best effort on stop/error: USB may already be disconnected.
                    try { WriteColor(0, 0, 0); } catch (Win32Exception) { }
                    catch (InvalidOperationException) { }
                }
            }
            finally { disposed = true; handle.Dispose(); }
        }
    }

    public sealed class HidInterfaceInfo
    {
        public string Path;
        public int OutputReportByteLength = -1;
        public ushort UsagePage;
        public ushort Usage;
        public byte[] SupportedRgbReports = new byte[0];
    }

    // Cache a palette and seed once per execution. Frames depend on elapsed time,
    // so skipped/delayed frames do not change the pace or random sequence.
    public sealed class EffectRenderer
    {
        readonly string effect;
        readonly byte red, green, blue;
        readonly int brightness, period, seed;
        readonly byte[][] palette;

        public EffectRenderer(string effect, byte red, byte green, byte blue,
            int brightness, int period, string colors, int seed)
        {
            this.effect = effect;
            this.red = red; this.green = green; this.blue = blue;
            this.brightness = brightness; this.period = period; this.seed = seed;
            string[] values = colors.Split(',');
            if (values.Length < 2 || values.Length > 16)
                throw new ArgumentException("A palette requires 2 to 16 RGB colors.");
            palette = new byte[values.Length][];
            for (int i = 0; i < values.Length; i++)
            {
                string hex = values[i].Trim().TrimStart('#');
                if (!Regex.IsMatch(hex, @"^[0-9a-fA-F]{6}$"))
                    throw new ArgumentException("Invalid RGB palette color: " + values[i]);
                palette[i] = new byte[] {
                    Convert.ToByte(hex.Substring(0, 2), 16),
                    Convert.ToByte(hex.Substring(2, 2), 16),
                    Convert.ToByte(hex.Substring(4, 2), 16)
                };
            }
        }

        public byte[] Frame(double elapsedSeconds)
        {
            return Controller.RenderFrameCore(effect, red, green, blue, brightness,
                period, elapsedSeconds, palette, seed);
        }
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
                BuildColorReport(red, green, blue)
            };
            byte[][] reports = new byte[commands.Length][];
            for (int i = 0; i < commands.Length; i++)
            {
                reports[i] = new byte[16];
                Array.Copy(commands[i], reports[i], commands[i].Length);
            }
            return reports;
        }

        public static byte[] BuildColorReport(byte red, byte green, byte blue)
        {
            byte[] report = new byte[16];
            byte[] data = new byte[] { 0xCB, 0x03, 0x1C, red, 0x16, green, 0x17, blue };
            Array.Copy(data, report, data.Length);
            return report;
        }

        public static byte[] RenderFrame(string effect, byte red, byte green, byte blue,
            int brightness, int periodSeconds, double elapsedSeconds)
        {
            return new EffectRenderer(effect, red, green, blue, brightness, periodSeconds,
                "FF0000,00FF00,0000FF", 0).Frame(elapsedSeconds);
        }

        static double[] Hue(double h)
        {
            int sector = (int)h;
            double t = (h - sector) * 255;
            switch (sector)
            {
                case 0: return new double[] { 255, t, 0 };
                case 1: return new double[] { 255 - t, 255, 0 };
                case 2: return new double[] { 0, 255, t };
                case 3: return new double[] { 0, 255 - t, 255 };
                case 4: return new double[] { t, 0, 255 };
                default: return new double[] { 255, 0, 255 - t };
            }
        }

        static double Smooth(double value) { return value * value * (3 - 2 * value); }

        static double[] RandomColor(uint index, int seed)
        {
            // A stateless uint mixer avoids a mutable RNG per frame and makes
            // preview, replay and startup reproduce the same colors for a seed.
            uint value;
            unchecked
            {
                value = index + (uint)seed + 0x9E3779B9u;
                value = (value ^ (value >> 16)) * 0x7FEB352Du;
                value = (value ^ (value >> 15)) * 0x846CA68Bu;
                value ^= value >> 16;
            }
            return Hue((value & 0xFFFFFFu) / 16777216.0 * 6);
        }

        internal static byte[] RenderFrameCore(string effect, byte red, byte green, byte blue,
            int brightness, int periodSeconds, double elapsedSeconds, byte[][] palette, int seed)
        {
            if (brightness < 0 || brightness > 100) throw new ArgumentOutOfRangeException("brightness");
            if (periodSeconds < 1 || periodSeconds > 3600) throw new ArgumentOutOfRangeException("periodSeconds");
            if (Double.IsNaN(elapsedSeconds) || Double.IsInfinity(elapsedSeconds) || elapsedSeconds < 0)
                throw new ArgumentOutOfRangeException("elapsedSeconds");
            double phase = (elapsedSeconds % periodSeconds) / periodSeconds;
            double scale = brightness / 100.0;
            double r = red, g = green, b = blue;
            if (String.Equals(effect, "Breathe", StringComparison.OrdinalIgnoreCase))
                scale *= (1 - Math.Cos(2 * Math.PI * phase)) / 2;
            else if (String.Equals(effect, "Blink", StringComparison.OrdinalIgnoreCase))
                scale *= phase < 0.5 ? 1 : 0;
            else if (String.Equals(effect, "Heartbeat", StringComparison.OrdinalIgnoreCase))
            {
                // Two soft pulses, then rest: strong at 10%, softer at 35%.
                double pulse = 0;
                if (phase < 0.20) pulse = Math.Pow(Math.Sin(Math.PI * phase / 0.20), 2);
                else if (phase >= 0.25 && phase < 0.45)
                    pulse = 0.75 * Math.Pow(Math.Sin(Math.PI * (phase - 0.25) / 0.20), 2);
                scale *= pulse;
            }
            else if (String.Equals(effect, "Rainbow", StringComparison.OrdinalIgnoreCase))
            {
                double[] color = Hue(phase * 6);
                r = color[0]; g = color[1]; b = color[2];
            }
            else if (String.Equals(effect, "Cycle", StringComparison.OrdinalIgnoreCase))
            {
                double position = phase * palette.Length;
                int index = (int)position;
                double blend = Smooth(position - index);
                byte[] from = palette[index], to = palette[(index + 1) % palette.Length];
                r = from[0] + (to[0] - from[0]) * blend;
                g = from[1] + (to[1] - from[1]) * blend;
                b = from[2] + (to[2] - from[2]) * blend;
            }
            else if (String.Equals(effect, "Random", StringComparison.OrdinalIgnoreCase))
            {
                uint index = (uint)(Math.Floor(elapsedSeconds / periodSeconds) % 4294967296.0);
                double[] from = RandomColor(index, seed), to = RandomColor(unchecked(index + 1), seed);
                double blend = Smooth(phase);
                r = from[0] + (to[0] - from[0]) * blend;
                g = from[1] + (to[1] - from[1]) * blend;
                b = from[2] + (to[2] - from[2]) * blend;
            }
            else if (!String.Equals(effect, "Static", StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException("Unknown effect: " + effect);

            return new byte[] {
                (byte)Math.Round(r * scale, MidpointRounding.AwayFromZero),
                (byte)Math.Round(g * scale, MidpointRounding.AwayFromZero),
                (byte)Math.Round(b * scale, MidpointRounding.AwayFromZero)
            };
        }

        internal static void WriteReport(SafeFileHandle handle, byte[] report)
        {
            uint written;
            if (!WriteFile(handle, report, 16, out written, IntPtr.Zero))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if (written != 16) throw new InvalidOperationException("Incomplete HID write; reconnect the headset and try again.");
        }

        public static DeviceConnection Open(bool clearOnDispose)
        {
            List<HidInterfaceInfo> interfaces = new List<HidInterfaceInfo>();
            foreach (string path in GetPaths())
                interfaces.Add(Inspect(path));
            string selectedPath = SelectControlInterface(interfaces.ToArray());

            SafeFileHandle handle = CreateFileW(
                selectedPath, 0x40000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
            try
            {
                if (handle.IsInvalid)
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                byte[][] reports = BuildReports(0, 0, 0);
                // Initialize once. Animated frames only send the CB color report.
                for (int i = 0; i < 4; i++)
                {
                    WriteReport(handle, reports[i]);
                    System.Threading.Thread.Sleep(30);
                }
                return new DeviceConnection(handle, clearOnDispose);
            }
            catch { handle.Dispose(); throw; }
        }
    }
}
'@
        Write-HS80StartupLog 'controller compilation finished'
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

    $baseColor = @(for ($i = 0; $i -lt 6; $i += 2) {
        [byte][Convert]::ToInt32($hexColor.Substring($i, 2), 16)
    })
    $renderer = New-Object HS80Rgb.EffectRenderer($Effect, $baseColor[0], $baseColor[1], $baseColor[2], $Brightness, $Period, $palette, $Seed)
    $channels = $renderer.Frame(0)

    if ($Preview) {
        [pscustomobject]@{
            Version = $programVersion
            Effect = $Effect
            Color = '#' + $hexColor
            Brightness = $Brightness
            Period = $Period
            Colors = $palette
            Seed = $Seed
            RunsContinuously = $isAnimation
            StartupParameters = $startupParameters
            EffectiveColor = '#{0:X2}{1:X2}{2:X2}' -f $channels[0], $channels[1], $channels[2]
            Reports = @([HS80Rgb.Controller]::BuildReports($channels[0], $channels[1], $channels[2]) | ForEach-Object {
                [BitConverter]::ToString($_)
            })
            Samples = @(if ($isAnimation) {
                foreach ($time in @(0, ($Period / 4.0), ($Period / 2.0), ($Period * 3.0 / 4.0))) {
                    $sample = $renderer.Frame($time)
                    [pscustomobject]@{ Seconds = $time; Color = '#{0:X2}{1:X2}{2:X2}' -f $sample[0], $sample[1], $sample[2] }
                }
            })
        }
        return
    }

    Write-HS80StartupLog 'waiting for controller ownership'
    $lease = [HS80Rgb.ControlLease]::AcquireDefault()
    Write-HS80StartupLog 'controller ownership acquired'
    $device = $null
    try {
        if ($Stop) {
            Write-Output 'Animacao anterior encerrada, se estava em execucao. Inicializacao do Windows preservada.'
            return
        }
        Write-HS80StartupLog 'USB detection and initialization started'
        $device = [HS80Rgb.Controller]::Open($isAnimation)
        Write-HS80StartupLog 'USB initialized'
        if ($isAnimation) {
            Write-Output ('Efeito {0}, brilho {1}%, periodo {2}s. Ctrl+C ou -Stop em outro terminal para parar e apagar.' -f $Effect, $Brightness, $Period)
            $clock = [Diagnostics.Stopwatch]::StartNew()
            Write-HS80StartupLog ('animation started: ' + $Effect)
            while (-not $lease.StopRequested) {
                $frame = $renderer.Frame($clock.Elapsed.TotalSeconds)
                $device.WriteColor($frame[0], $frame[1], $frame[2])
                if ($lease.WaitForStop(50)) { break }
            }
        } else {
            $device.WriteColor($channels[0], $channels[1], $channels[2])
            Write-HS80StartupLog ('static color applied: #' + $hexColor)
            Write-Output ('Comandos enviados: #{0}, brilho {1}%. Conexao encerrada.' -f $hexColor, $Brightness)
        }
    } finally {
        # Keep the lease until the old animation has cleared LEDs and closed USB.
        try { if ($null -ne $device) { $device.Dispose() } }
        finally { $lease.Dispose(); Write-HS80StartupLog 'controller closed' }
    }
} catch {
    Write-HS80StartupLog ('error: ' + $_.Exception.Message)
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
