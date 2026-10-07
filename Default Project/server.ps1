# ============================================================================
#  server.ps1 - entry point for the Barangay Complaint & Concern Reporting System
#
#  Usage:
#      .\start.bat                     (recommended - double click)
#      .\server.ps1                    (PowerShell)
#      .\server.ps1 -Port 8090         (different port)
#      .\server.ps1 -Reset             (wipe the database and start fresh)
#
#  Requires: Windows PowerShell 5.1 or newer. No other software needed.
# ============================================================================

[CmdletBinding()]
param(
    [int]$Port = 0,
    [switch]$Reset,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

$global:AppRoot = $PSScriptRoot

# ---------------------------------------------------------------- load code --
$modules = @(
    'app\Core.ps1'
    'app\Database.ps1'
    'app\Security.ps1'
    'app\Validation.ps1'
    'app\Views.ps1'
    'app\Controllers\StaticController.ps1'
    'app\Controllers\AuthController.ps1'
    'app\Controllers\PublicController.ps1'
    'app\Controllers\ComplaintController.ps1'
    'app\Controllers\UserController.ps1'
)

foreach ($module in $modules) {
    $full = Join-Path $global:AppRoot $module
    if (-not (Test-Path -LiteralPath $full)) {
        Write-Host ("  ERROR: missing module '{0}'" -f $module) -ForegroundColor Red
        exit 1
    }
    try {
        . $full
    }
    catch {
        Write-Host ''
        Write-Host ('  ERROR while loading {0}' -f $module) -ForegroundColor Red
        Write-Host ('  ' + $_.Exception.Message) -ForegroundColor Yellow
        Write-Host ('  Line ' + $_.InvocationInfo.ScriptLineNumber + ': ' + $_.InvocationInfo.Line.Trim()) -ForegroundColor DarkGray
        Write-Host ''
        Read-Host 'Press Enter to exit'
        exit 1
    }
}

# ------------------------------------------------------------------- start ---
Initialize-App -Port $Port -Reset:$Reset -NoBrowser:$NoBrowser

if (-not $NoBrowser) {
    Open-LandingPage
}

try {
    Start-WebServer
}
catch {
    Write-Host ''
    Write-Host ('  ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ''
    Read-Host 'Press Enter to exit'
    exit 1
}
