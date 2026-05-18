$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$root = (Resolve-Path (Join-Path $scriptDir "..")).Path
$runtime = Join-Path $root "tcltk"
$runtimeBin = Join-Path $runtime "bin"
$wish = Join-Path $runtimeBin "wish90.exe"
$tclsh = Join-Path $runtimeBin "tclsh90.exe"
$app = Join-Path $root "tcl\app.tcl"

if (!(Test-Path -LiteralPath $wish)) {
    Write-Error "Pino UI runtime not found: $wish"
    exit 1
}

if (!(Test-Path -LiteralPath $app)) {
    Write-Error "Pino UI entrypoint not found: $app"
    exit 1
}

$env:PINO_ROOT = $root
$env:PINO_TCLTK = $runtime
if (!$env:PINO_WORKSPACE) {
    $env:PINO_WORKSPACE = (Get-Location).Path
}
$env:PATH = "$runtimeBin;$env:PATH"

$launcher = $wish
if ($args -contains "--check" -or $args -contains "--repo-check" -or $args -contains "--restore-check" -or $args -contains "--gui-check") {
    $launcher = $tclsh
}

& $launcher $app @args
exit $LASTEXITCODE