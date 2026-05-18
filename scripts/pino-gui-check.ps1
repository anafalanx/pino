param(
    [string]$Workspace,
    [string]$OutputDir,
    [int]$AutoExitMs = 1500,
    [int]$TimeoutSeconds = 15,
    [int]$MinScreenshotWidth = 800,
    [int]$MinScreenshotHeight = 500,
    [int]$MinSampleColors = 4,
    [switch]$Embedded,
    [switch]$ExerciseDialogError
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$root = (Resolve-Path (Join-Path $scriptDir "..")).Path
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

if (!$OutputDir) {
    $OutputDir = Join-Path $root ".pino-dev\gui-check\$timestamp"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

if (!$Workspace) {
    $Workspace = Join-Path $OutputDir "workspace"
    New-Item -ItemType Directory -Path (Join-Path $Workspace "notes") -Force | Out-Null
    Set-Content -Path (Join-Path $Workspace "notes\today.md") -Value "# Today`n`nA small note for the GUI verification run." -Encoding utf8
    Set-Content -Path (Join-Path $Workspace "scratch.txt") -Value "Pino GUI harness sample file." -Encoding utf8
}
$Workspace = [System.IO.Path]::GetFullPath($Workspace)

$stdoutPath = Join-Path $OutputDir "stdout.txt"
$stderrPath = Join-Path $OutputDir "stderr.txt"
$diagnosticsPath = Join-Path $OutputDir "diagnostics.log"
$readyPath = Join-Path $OutputDir "ready.txt"
$windowsPath = Join-Path $OutputDir "windows.txt"
$screenshotsDir = Join-Path $OutputDir "screenshots"
New-Item -ItemType Directory -Path $screenshotsDir -Force | Out-Null
Remove-Item -LiteralPath $stdoutPath, $stderrPath, $diagnosticsPath, $readyPath, $windowsPath -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $screenshotsDir "*.png") -Force -ErrorAction SilentlyContinue

$runtime = Join-Path $root "tcltk"
$runtimeBin = Join-Path $runtime "bin"
$tclsh = Join-Path $runtimeBin "tclsh90.exe"
$app = Join-Path $root "tcl\app.tcl"

if (!(Test-Path -LiteralPath $tclsh)) {
    throw "Pino Tcl runtime not found: $tclsh"
}
if (!(Test-Path -LiteralPath $app)) {
    throw "Pino Tcl app not found: $app"
}

if ($Embedded) {
    $launcher = Join-Path $root "pino.exe"
    & go build -o $launcher .\cmd\pino
    if ($LASTEXITCODE -ne 0) {
        throw "go build failed while preparing pino.exe"
    }
    $launcherArgs = @("--gui-check")
}
else {
    $launcher = $tclsh
    $launcherArgs = @($app, "--gui-check")
}
if ($ExerciseDialogError) {
    $launcherArgs += "--dialog-error-check"
}

try {
    Add-Type -AssemblyName System.Drawing.Common
}
catch {
    Add-Type -AssemblyName System.Drawing
}
$windowCaptureSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class PinoWindowCapture
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int command);

    public static string VisibleWindows(int[] processIds)
    {
        StringBuilder output = new StringBuilder();

        EnumWindows(delegate (IntPtr hWnd, IntPtr lParam) {
            uint windowProcessId;
            GetWindowThreadProcessId(hWnd, out windowProcessId);
            if (!Contains(processIds, (int)windowProcessId) || !IsWindowVisible(hWnd)) {
                return true;
            }

            Rect rect;
            if (!GetWindowRect(hWnd, out rect)) {
                return true;
            }
            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            if (width < 16 || height < 16) {
                return true;
            }

            ShowWindow(hWnd, 9);
            SetForegroundWindow(hWnd);

            string title = WindowTitle(hWnd);
            output.Append((int)windowProcessId).Append('\t')
                .Append(rect.Left).Append('\t')
                .Append(rect.Top).Append('\t')
                .Append(width).Append('\t')
                .Append(height).Append('\t')
                .Append(title.Replace('\t', ' ')).Append('\n');
            return true;
        }, IntPtr.Zero);

        return output.ToString();
    }

    private static string WindowTitle(IntPtr hWnd)
    {
        int length = GetWindowTextLength(hWnd);
        if (length <= 0) {
            return "window";
        }
        StringBuilder builder = new StringBuilder(length + 1);
        GetWindowText(hWnd, builder, builder.Capacity);
        string title = builder.ToString().Trim();
        return title.Length == 0 ? "window" : title;
    }

    private static bool Contains(int[] values, int target)
    {
        foreach (int value in values) {
            if (value == target) {
                return true;
            }
        }
        return false;
    }

}
'@
Add-Type -TypeDefinition $windowCaptureSource

function Get-SafeFileName {
    param([string]$Value)

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $builder = [System.Text.StringBuilder]::new()
    foreach ($character in $Value.ToCharArray()) {
        if ($invalid -contains $character) {
            [void]$builder.Append('_')
        }
        else {
            [void]$builder.Append($character)
        }
    }
    $safe = $builder.ToString().Trim()
    if (!$safe) {
        $safe = "window"
    }
    if ($safe.Length -gt 60) {
        $safe = $safe.Substring(0, 60)
    }
    return $safe
}

function Save-WindowScreenshots {
    param(
        [int[]]$ProcessIds,
        [string]$Directory,
        [string]$WindowListPath
    )

    $count = 0
    $windows = [PinoWindowCapture]::VisibleWindows($ProcessIds)
    [System.IO.File]::WriteAllText($WindowListPath, $windows, [System.Text.UTF8Encoding]::new($false))
    [System.Threading.Thread]::Sleep(200)
    foreach ($line in ($windows -split "`n")) {
        if (!$line.Trim()) {
            continue
        }
        $parts = $line -split "`t", 6
        if ($parts.Count -lt 6) {
            continue
        }
        $left = [int]$parts[1]
        $top = [int]$parts[2]
        $width = [int]$parts[3]
        $height = [int]$parts[4]
        $title = Get-SafeFileName $parts[5]
        $path = Join-Path $Directory ("{0:D2}-{1}.png" -f $count, $title)
        $bitmap = $null
        $graphics = $null
        try {
            $bitmap = [System.Drawing.Bitmap]::new($width, $height)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.CopyFromScreen($left, $top, 0, 0, [System.Drawing.Size]::new($width, $height))
            $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
            $count++
        }
        finally {
            if ($graphics) { $graphics.Dispose() }
            if ($bitmap) { $bitmap.Dispose() }
        }
    }
    return $count
}

function Test-ScreenshotArtifacts {
    param(
        [string]$Directory,
        [int]$MinimumWidth,
        [int]$MinimumHeight,
        [int]$MinimumSampleColors
    )

    $screenshots = Get-ChildItem -LiteralPath $Directory -Filter "*.png" -File
    if ($screenshots.Count -le 0) {
        throw "No screenshot files were written in $Directory"
    }

    foreach ($screenshot in $screenshots) {
        $bitmap = $null
        try {
            $bitmap = [System.Drawing.Bitmap]::FromFile($screenshot.FullName)
            if ($bitmap.Width -lt $MinimumWidth -or $bitmap.Height -lt $MinimumHeight) {
                throw "Screenshot $($screenshot.Name) is too small: $($bitmap.Width)x$($bitmap.Height)"
            }

            $sampledColors = @{}
            for ($sampleY = 0; $sampleY -lt 8; $sampleY++) {
                $pixelY = [int][Math]::Round($sampleY * ($bitmap.Height - 1) / 7)
                for ($sampleX = 0; $sampleX -lt 12; $sampleX++) {
                    $pixelX = [int][Math]::Round($sampleX * ($bitmap.Width - 1) / 11)
                    $colorKey = $bitmap.GetPixel($pixelX, $pixelY).ToArgb().ToString()
                    $sampledColors[$colorKey] = $true
                    if ($sampledColors.Count -ge $MinimumSampleColors) {
                        break
                    }
                }
                if ($sampledColors.Count -ge $MinimumSampleColors) {
                    break
                }
            }

            if ($sampledColors.Count -lt $MinimumSampleColors) {
                throw "Screenshot $($screenshot.Name) appears visually blank: only $($sampledColors.Count) sampled colors"
            }
        }
        finally {
            if ($bitmap) { $bitmap.Dispose() }
        }
    }
}

function Get-ProcessTreeIds {
    param([int]$RootId)

    $seen = @{}
    $queue = [System.Collections.Generic.Queue[int]]::new()
    $result = [System.Collections.Generic.List[int]]::new()
    $seen[$RootId] = $true
    $queue.Enqueue($RootId)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $result.Add($current)
        $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$current" -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            $childId = [int]$child.ProcessId
            if (!$seen.ContainsKey($childId)) {
                $seen[$childId] = $true
                $queue.Enqueue($childId)
            }
        }
    }

    return $result.ToArray()
}

$processInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processInfo.FileName = $launcher
$processInfo.WorkingDirectory = $root
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.CreateNoWindow = $false
foreach ($argument in $launcherArgs) {
    [void]$processInfo.ArgumentList.Add($argument)
}
$processInfo.Environment["PINO_ROOT"] = $root
$processInfo.Environment["PINO_TCLTK"] = $runtime
$processInfo.Environment["PINO_WORKSPACE"] = $Workspace
$processInfo.Environment["PINO_DIAGNOSTICS_LOG"] = $diagnosticsPath
$processInfo.Environment["PINO_GUI_READY_FILE"] = $readyPath
$processInfo.Environment["PINO_GUI_AUTO_EXIT_MS"] = [string]$AutoExitMs
$processInfo.Environment["PINO_NO_ERROR_DIALOGS"] = "1"
$processInfo.Environment["PATH"] = "$runtimeBin;$($processInfo.Environment["PATH"])"

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $processInfo

Write-Host "Launching Pino GUI check..."
Write-Host "Artifacts: $OutputDir"
Write-Host "Workspace: $Workspace"

[void]$process.Start()
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()

$ready = $false
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath $readyPath) {
        $ready = $true
        break
    }
    if ($process.HasExited) {
        break
    }
    [void]$process.WaitForExit(100)
}

$captureCount = 0
if ($ready -or !$process.HasExited) {
    $processIds = Get-ProcessTreeIds -RootId $process.Id
    $captureCount = Save-WindowScreenshots -ProcessIds $processIds -Directory $screenshotsDir -WindowListPath $windowsPath
}

$timedOut = $false
if (!$process.WaitForExit([Math]::Max(1000, $AutoExitMs + 5000))) {
    $timedOut = $true
    foreach ($processId in (Get-ProcessTreeIds -RootId $process.Id)) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
    [void]$process.WaitForExit(2000)
}

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($stdoutPath, $stdout, $utf8)
[System.IO.File]::WriteAllText($stderrPath, $stderr, $utf8)

$diagnostics = ""
if (Test-Path -LiteralPath $diagnosticsPath) {
    $diagnostics = Get-Content -LiteralPath $diagnosticsPath -Raw
}

Write-Host "Ready marker: $readyPath"
Write-Host "Screenshots: $screenshotsDir ($captureCount captured)"
Write-Host "windows: $windowsPath"
Write-Host "stdout: $stdoutPath"
Write-Host "stderr: $stderrPath"
Write-Host "diagnostics: $diagnosticsPath"

if ($stdout.Trim().Length -gt 0) {
    Write-Host "--- stdout ---"
    Write-Host $stdout.TrimEnd()
}
if ($stderr.Trim().Length -gt 0) {
    Write-Host "--- stderr ---"
    Write-Host $stderr.TrimEnd()
}
if ($diagnostics.Trim().Length -gt 0) {
    Write-Host "--- diagnostics ---"
    Write-Host $diagnostics.TrimEnd()
}

if ($timedOut) {
    throw "Pino GUI check timed out after $TimeoutSeconds seconds. Captured artifacts are in $OutputDir"
}
if (!$ready) {
    throw "Pino GUI did not report readiness. Captured artifacts are in $OutputDir"
}
if ($captureCount -le 0) {
    throw "No Pino GUI windows were captured. Captured artifacts are in $OutputDir"
}
Test-ScreenshotArtifacts -Directory $screenshotsDir -MinimumWidth $MinScreenshotWidth -MinimumHeight $MinScreenshotHeight -MinimumSampleColors $MinSampleColors

$combinedOutput = "$stdout`n$stderr`n$diagnostics"
if ($ExerciseDialogError) {
    if ($combinedOutput -notmatch [regex]::Escape("Pino dialog capture check")) {
        throw "Dialog-error exercise did not reach diagnostics. Captured artifacts are in $OutputDir"
    }
    Write-Host "Dialog-error capture verified."
    exit 0
}

if ($process.ExitCode -ne 0) {
    throw "Pino GUI exited with code $($process.ExitCode). Captured artifacts are in $OutputDir"
}
if ($combinedOutput -match "\[ERROR\]") {
    throw "Pino GUI logged errors. Captured artifacts are in $OutputDir"
}

Write-Host "Pino GUI check passed."