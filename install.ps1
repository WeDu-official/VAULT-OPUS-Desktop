# ------------------------------------------------------------------------------
# VAULT_OPUS - WINDOWS INSTALLER (PowerShell Edition)
# Fully Self-Contained - No External Tools Required
# ------------------------------------------------------------------------------
param(
    [switch]$SkipNode,
    [switch]$SkipFrontend,
    [switch]$AutoInstall,
    [switch]$Uninstall,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------

$LogFile = "$env:TEMP\vault_opus_install.log"
$TempDir = "$env:TEMP\vault_opus_install"
$PythonVersion = "3.12.3"
$NodeVersion = "22.13.0"

# Ensure temp directory exists
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

# Start logging
Start-Transcript -Path $LogFile -Append | Out-Null

# ANSI support
$ESC = [char]27
if (-not $env:NO_COLOR) {
    $RED    = "${ESC}[31m"
    $GREEN  = "${ESC}[32m"
    $BLUE   = "${ESC}[34m"
    $CYAN   = "${ESC}[36m"
    $YELLOW = "${ESC}[33m"
    $BOLD   = "${ESC}[1m"
    $NC     = "${ESC}[0m"
} else {
    $RED=""; $GREEN=""; $BLUE=""; $CYAN=""; $YELLOW=""; $BOLD=""; $NC=""
}

# ------------------------------------------------------------------------------
# Logging Functions
# ------------------------------------------------------------------------------

function Log-Info($msg)    { Write-Host "${BLUE}[INFO]${NC} $msg" }
function Log-Success($msg) { Write-Host "${GREEN}[SUCCESS]${NC} $msg" }
function Log-Warning($msg) { Write-Host "${YELLOW}[WARNING]${NC} $msg" }
function Log-Error($msg)   { Write-Host "${RED}[ERROR]${NC} $msg" }
function Log-Step($msg)    { Write-Host "`n${CYAN}${BOLD}>>> $msg${NC}" }

function Die($msg) {
    Log-Error $msg
    Stop-Transcript | Out-Null
    exit 1
}

# ------------------------------------------------------------------------------
# Admin Check & Auto-Elevate
# ------------------------------------------------------------------------------

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "${YELLOW}[WARNING]${NC} Administrator privileges required."
    Write-Host "${CYAN}[INFO]${NC} Relaunching as Administrator..."

    $argsList = @()
    if ($SkipNode)      { $argsList += "-SkipNode" }
    if ($SkipFrontend)  { $argsList += "-SkipFrontend" }
    if ($AutoInstall)   { $argsList += "-AutoInstall" }
    if ($Uninstall)     { $argsList += "-Uninstall" }

    Start-Process powershell -Verb RunAs -ArgumentList (
        "-ExecutionPolicy Bypass -File `"$PSCommandPath`" " + ($argsList -join " ")
    )
    exit
}

Log-Success "Running with Administrator privileges."

# ------------------------------------------------------------------------------
# Help
# ------------------------------------------------------------------------------

if ($Help) {
    Write-Host @"

Usage:
    .\install.bat [options]
    powershell -ExecutionPolicy Bypass -File install.ps1 [options]

Options:
    -SkipNode        Skip Node.js installation
    -SkipFrontend    Skip frontend npm install
    -AutoInstall     Automatically answer Yes to all prompts
    -Uninstall       Remove venv, node_modules, and config backups
    -Help            Show this help message

Examples:
    .\install.bat -AutoInstall
    .\install.bat -AutoInstall -SkipFrontend

"@
    Stop-Transcript | Out-Null
    exit 0
}

# ------------------------------------------------------------------------------
# Uninstall
# ------------------------------------------------------------------------------

if ($Uninstall) {
    Write-Host ""
    Write-Host "${BOLD}Uninstalling VAULT_OPUS...${NC}"

    if (Test-Path "venv") {
        Remove-Item "venv" -Recurse -Force
        Log-Info "Removed venv"
    }

    if (Test-Path "src\WI\client\node_modules") {
        Remove-Item "src\WI\client\node_modules" -Recurse -Force
        Log-Info "Removed client node_modules"
    }

    if (Test-Path "src\WI\mobile\node_modules") {
        Remove-Item "src\WI\mobile\node_modules" -Recurse -Force
        Log-Info "Removed mobile node_modules"
    }

    Get-ChildItem "src" -Filter "config.json.bak.*" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Log-Success "Uninstall complete."
    Stop-Transcript | Out-Null
    exit 0
}

# ------------------------------------------------------------------------------
# Banner
# ------------------------------------------------------------------------------

Clear-Host
Write-Host "${CYAN}${BOLD}"
Write-Host " __      __    _    _   _ _   _______    ____   _____  _    _  _____ "
Write-Host " \ \    / /   / \  | | | | | |__   __|  / __ \ |  __ \| |  | |/ ____|"
Write-Host "  \ \  / /   / _ \ | | | | |    | |    | |  | || |__) | |  | | (___  "
Write-Host "   \ \/ /   / ___ \| | | | |    | |    | |  | ||  ___/| |  | |\___ \ "
Write-Host "    \  /   / /   \ \ |_| | |____| |    | |__| || |    | |__| |____) |"
Write-Host "     \/   /_/     \_\____|______|_|     \____/ |_|     \____/|_____/ "
Write-Host "${NC}"
Write-Host ""
Write-Host "${BLUE}${BOLD}>>> THE INFINITY CLOUD STORAGE PROJECT <<<${NC}"
Write-Host ""

# ------------------------------------------------------------------------------
# Universal Download Function (works on all PowerShell versions)
# ------------------------------------------------------------------------------

function Download-File($Url, $OutFile) {
    $parent = Split-Path -Parent $OutFile
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    Log-Info "Downloading from $Url ..."

    try {
        if ($PSVersionTable.PSVersion -ge [version]"3.0") {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 300
        } else {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($Url, $OutFile)
        }
        return $true
    }
    catch {
        Log-Warning "Download failed: $_"
        return $false
    }
}

# ------------------------------------------------------------------------------
# Refresh Environment Path
# ------------------------------------------------------------------------------

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# ------------------------------------------------------------------------------
# STEP 1: Python Bootstrap (Self-Contained)
# ------------------------------------------------------------------------------

Log-Step "STEP 1: Python Bootstrap"

function Find-Python {
    # Check common Python paths
    $candidates = @(
        "python",
        "python3",
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python39\python.exe",
        "C:\Python312\python.exe",
        "C:\Python311\python.exe",
        "C:\Python310\python.exe",
        "C:\Program Files\Python312\python.exe",
        "C:\Program Files\Python311\python.exe",
        "C:\Program Files\Python310\python.exe"
    )

    foreach ($cand in $candidates) {
        $cmd = Get-Command $cand -ErrorAction SilentlyContinue
        if ($cmd) {
            try {
                $verStr = & $cmd.Source --version 2>&1
                if ($verStr -match "Python (\d+)\.(\d+)") {
                    $major = [int]$matches[1]
                    $minor = [int]$matches[2]
                    if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 8)) {
                        return $cmd.Source
                    }
                }
            } catch { }
        }
    }
    return $null
}

$PythonExe = Find-Python

if (-not $PythonExe) {
    Log-Warning "Python 3.8+ not found. Will install automatically."

    if (-not $AutoInstall) {
        $resp = Read-Host "Install Python $PythonVersion automatically? (y/n)"
        if ($resp -ne "y") { Die "Python 3.8+ is required." }
    }

    # Try winget first
    $installed = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Log-Info "Attempting installation via winget..."
        try {
            $proc = Start-Process -FilePath "winget" -ArgumentList @(
                "install", "--id", "Python.Python.3.12",
                "-e", "--accept-source-agreements", "--accept-package-agreements"
            ) -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -eq 0) { $installed = $true }
        } catch { }
    }

    # Fallback: Direct download of standalone installer
    if (-not $installed) {
        Log-Info "Downloading Python $PythonVersion installer directly..."
        $pyUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
        $pyInstaller = "$TempDir\python_installer.exe"

        if (Download-File -Url $pyUrl -OutFile $pyInstaller) {
            Log-Info "Installing Python silently (this may take a few minutes)..."
            $proc = Start-Process -FilePath $pyInstaller -ArgumentList @(
                "/quiet", "InstallAllUsers=0",
                "PrependPath=1", "Include_test=0",
                "Include_doc=0", "Include_launcher=1"
            ) -Wait -PassThru

            if ($proc.ExitCode -eq 0) {
                $installed = $true
                Log-Success "Python installed successfully."
            } else {
                Log-Warning "Python installer exited with code $($proc.ExitCode)"
            }

            Remove-Item $pyInstaller -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $installed) {
        Die @"
Python installation failed automatically.
Please install Python 3.8+ manually from https://python.org/downloads/
Make sure to check "Add Python to PATH" during installation.
"@
    }

    Refresh-Path
    Start-Sleep -Seconds 2

    # Re-check for Python
    $PythonExe = Find-Python
    if (-not $PythonExe) {
        Die "Python was installed but cannot be found in PATH. Please restart your computer and try again."
    }
}

# Verify Python version
try {
    $verCheck = & $PythonExe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
    Log-Success "Python $verCheck ready at: $PythonExe"
} catch {
    Die "Python verification failed."
}

# ------------------------------------------------------------------------------
# STEP 2: Node.js Bootstrap (Self-Contained)
# ------------------------------------------------------------------------------

Log-Step "STEP 2: Node.js Bootstrap"

$HAS_NODE = $false

if ($SkipNode) {
    Log-Warning "Node.js installation skipped by user."
} else {
    function Find-Node {
        $nodeCmd = Get-Command "node" -ErrorAction SilentlyContinue
        $npmCmd = Get-Command "npm" -ErrorAction SilentlyContinue

        if ($nodeCmd -and $npmCmd) {
            try {
                $nodeVer = & $nodeCmd.Source --version 2>$null
                $npmVer = & $npmCmd.Source --version 2>$null

                $nodeMajor = [int]($nodeVer -replace '^v' -split '\.' | Select-Object -First 1)
                $nodeMinor = [int]($nodeVer -replace '^v' -split '\.' | Select-Object -Index 1)
                $npmMajor = [int]($npmVer -replace '^v' -split '\.' | Select-Object -First 1)
                $npmMinor = [int]($npmVer -replace '^v' -split '\.' | Select-Object -Index 1)

                # Require Node >= 22.13.0 and npm >= 11.15.0
                $nodeOk = ($nodeMajor -gt 22) -or ($nodeMajor -eq 22 -and $nodeMinor -ge 13)
                $npmOk = ($npmMajor -gt 11) -or ($npmMajor -eq 11 -and $npmMinor -ge 15)

                if ($nodeOk -and $npmOk) {
                    return @{ Node = $nodeCmd.Source; NPM = $npmCmd.Source }
                } else {
                    Log-Warning "Found Node.js $nodeVer / npm $npmVer but requirements are >= 22.13.0 / >= 11.15.0"
                }
            } catch { }
        }
        return $null
    }

    $nodeTools = Find-Node

    if (-not $nodeTools) {
        Log-Warning "Node.js 22.13.0+ / npm 11.15.0+ not found. Will install automatically."

        if (-not $AutoInstall) {
            $resp = Read-Host "Install Node.js 22.13.0 LTS automatically? (y/n)"
            if ($resp -ne "y") {
                Log-Warning "Node.js not installed. Frontend will be disabled."
                $SkipFrontend = $true
            }
        }

        if (-not $SkipFrontend) {
            # Try winget first
            $installed = $false
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                Log-Info "Attempting Node.js installation via winget..."
                try {
                    $proc = Start-Process -FilePath "winget" -ArgumentList @(
                        "install", "OpenJS.NodeJS.LTS", "--version", "22.13.0",
                        "--accept-source-agreements", "--accept-package-agreements"
                    ) -Wait -PassThru -NoNewWindow
                    if ($proc.ExitCode -eq 0) { $installed = $true }
                } catch { }
            }

            # Fallback: Direct MSI download
            if (-not $installed) {
                Log-Info "Downloading Node.js 22.13.0 MSI installer directly..."
                $nodeUrl = "https://nodejs.org/dist/v22.13.0/node-v22.13.0-x64.msi"
                $nodeInstaller = "$TempDir\node_installer.msi"

                if (Download-File -Url $nodeUrl -OutFile $nodeInstaller) {
                    Log-Info "Installing Node.js silently..."
                    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList @(
                        "/i", "`"$nodeInstaller`"", "/quiet", "/norestart"
                    ) -Wait -PassThru

                    if ($proc.ExitCode -eq 0) {
                        $installed = $true
                        Log-Success "Node.js installed successfully."
                    } else {
                        Log-Warning "Node.js MSI exited with code $($proc.ExitCode)"
                    }

                    Remove-Item $nodeInstaller -Force -ErrorAction SilentlyContinue
                }
            }

            if (-not $installed) {
                Log-Warning @"
Node.js 22.13.0+ / npm 11.15.0+ automatic installation failed.
Frontend will be disabled. You can install manually from:
https://nodejs.org/dist/v22.13.0/node-v22.13.0-x64.msi
"@
                $SkipFrontend = $true
            }

            if (-not $SkipFrontend) {
                Refresh-Path
                Start-Sleep -Seconds 2

                # Re-check
                $nodeTools = Find-Node
                if (-not $nodeTools) {
                    Log-Warning "Node.js installed but not found in PATH or version mismatch. Frontend will be disabled."
                    $SkipFrontend = $true
                }
            }
        }
    }

    if ($nodeTools) {
        $HAS_NODE = $true
        $nodeVer = & $nodeTools.Node --version 2>$null
        $npmVer = & $nodeTools.NPM --version 2>$null
        Log-Success "Node.js $nodeVer / npm $npmVer ready (meets requirements)."
    }
}

# ------------------------------------------------------------------------------
# STEP 3: Virtual Environment & Python Dependencies
# ------------------------------------------------------------------------------

Log-Step "STEP 3: Virtual Environment & Python Dependencies"

Log-Info "Creating virtual environment..."

if (-not (Test-Path "venv")) {
    & $PythonExe -m venv venv
    if (-not $?) { Die "Failed to create virtual environment." }
}

$VenvPython = ".\venv\Scripts\python.exe"
$VenvPip = ".\venv\Scripts\pip.exe"

if (-not (Test-Path $VenvPython)) {
    Die "Virtual environment creation failed - python.exe not found in venv."
}

Log-Success "Virtual environment ready."

if (-not (Test-Path "requirements.txt")) {
    Die "requirements.txt not found in current directory."
}

Log-Info "Installing Python dependencies (up to 3 attempts)..."

$Success = $false
for ($i = 1; $i -le 3; $i++) {
    try {
        & $VenvPip install --no-cache-dir -r requirements.txt
        if ($?) {
            $Success = $true
            break
        }
    }
    catch {
        Log-Warning "Attempt $i failed. Retrying in 3 seconds..."
        Start-Sleep -Seconds 3
    }
}

if (-not $Success) {
    Die "pip install failed after 3 attempts. Check your requirements.txt and internet connection."
}

Log-Success "Python dependencies installed."

# ------------------------------------------------------------------------------
# STEP 4: Discord Configuration
# ------------------------------------------------------------------------------

Log-Step "STEP 4: Discord Bot Configuration"

New-Item -ItemType Directory -Force -Path "src" | Out-Null

$ConfigFile = "src\config.json"

if (-not (Test-Path $ConfigFile)) {
    $defaultConfig = @{
        discord = @{
            token = ""
            channel_id = ""
            command_prefix = "/"
        }
    }
    $defaultConfig | ConvertTo-Json -Depth 5 | Set-Content $ConfigFile
    Log-Info "Created default config.json"
} else {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Copy-Item $ConfigFile "src\config.json.bak.$timestamp" -Force
    Log-Info "Backed up existing config to config.json.bak.$timestamp"
}

$TOKEN = ""
$CHANNEL_ID = ""

if (-not $AutoInstall) {
    Write-Host ""
    Write-Host "${CYAN}Discord Bot Token (leave empty to keep existing):${NC} " -NoNewline
    $TOKEN = Read-Host
    Write-Host "${CYAN}Discord Channel ID (leave empty to keep existing):${NC} " -NoNewline
    $CHANNEL_ID = Read-Host
} else {
    Log-Info "Auto-install mode: keeping existing Discord config."
}

# Update config
$config = Get-Content $ConfigFile | ConvertFrom-Json

if ($TOKEN.Trim()) {
    $config.discord.token = $TOKEN.Trim()
}
if ($CHANNEL_ID.Trim()) {
    $config.discord.channel_id = $CHANNEL_ID.Trim()
}

$config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile

Log-Success "Configuration updated."

# ------------------------------------------------------------------------------
# STEP 5: Frontend npm Packages
# ------------------------------------------------------------------------------

Log-Step "STEP 5: Frontend Setup"

if ($SkipFrontend) {
    Log-Warning "Frontend npm install skipped."
} elseif (-not $HAS_NODE) {
    Log-Warning "Node.js unavailable. Skipping frontend."
} else {
    $frontendPrompt = $true

    if (-not $AutoInstall) {
        $resp = Read-Host "Install frontend npm packages for Web & Mobile? (y/n)"
        if ($resp -ne "y") { $frontendPrompt = $false }
    }

    if ($frontendPrompt) {
        $Dirs = @("src\WI\client", "src\WI\mobile")

        foreach ($dir in $Dirs) {
            $packageJson = Join-Path $dir "package.json"

            if (Test-Path $packageJson) {
                Log-Info "Running npm install in $dir ..."

                $originalDir = Get-Location
                try {
                    Set-Location $dir

                    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
                    if ($npmCmd) {
                        & $npmCmd.Source install
                        if ($?) {
                            Log-Success "npm install completed in $dir"
                        } else {
                            Log-Warning "npm install had issues in $dir"
                        }
                    }
                }
                catch {
                    Log-Warning "npm install failed in ${dir}: $_"
                }
                finally {
                    Set-Location $originalDir
                }
            } else {
                Log-Warning "No package.json found in $dir - skipping."
            }
        }

        Log-Success "Frontend setup complete."
    } else {
        Log-Info "Frontend installation skipped by user."
    }
}

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------

if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    Log-Info "Cleaned up temporary files."
}

# ------------------------------------------------------------------------------
# Final Message
# ------------------------------------------------------------------------------

Write-Host ""
Write-Host ""
Write-Host "${GREEN}${BOLD}==============================================${NC}"
Write-Host "${GREEN}${BOLD}  VAULT_OPUS INSTALLATION COMPLETE!${NC}"
Write-Host "${GREEN}${BOLD}==============================================${NC}"
Write-Host ""
Write-Host "${CYAN}Log file:${NC} $LogFile"
Write-Host ""
Write-Host "${BOLD}Run the app with:${NC}"
Write-Host ""
Write-Host "  CLI:"
Write-Host "    .\venv\Scripts\python.exe src\VAULT_OPUS.py"
Write-Host ""
Write-Host "  GUI Backend:"
Write-Host "    .\venv\Scripts\python.exe src\WI\server.py"
Write-Host ""
Write-Host "  Desktop GUI:"
Write-Host "    cd src\WI\client"
Write-Host "    npm install (DO IT FOR ONLY FIRST TIME)"
Write-Host "    npm run dev"
Write-Host ""
Write-Host "  Mobile GUI:"
Write-Host "    cd src\WI\mobile"
Write-Host "    npm install (DO IT FOR ONLY FIRST TIME)"
Write-Host "    npm run dev"
Write-Host ""
Write-Host "${CYAN}Enjoy!${NC}"
Write-Host ""

Stop-Transcript | Out-Null
