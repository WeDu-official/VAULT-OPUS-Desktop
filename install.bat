@echo off
setlocal enabledelayedexpansion
title VAULT_OPUS STANDALONE WINDOWS INSTALLER

:: --- Colors ---
:: Note: ANSI escape codes require modern Windows Terminal or Windows 10+
set "RED=[31m"
set "GREEN=[32m"
set "BLUE=[34m"
set "CYAN=[36m"
set "YELLOW=[33m"
set "BOLD=[1m"
set "NC=[0m"

:: --- Banner ---
cls
echo.
echo %CYAN%%BOLD% __      __    _    _   _ _   _______    ____   _____  _    _  _____ %NC%
echo %CYAN%%BOLD% \ \    / /   / \  | | | | | |__   __|  / __ \ |  __ \| |  | |/ ____|%NC%
echo %CYAN%%BOLD%  \ \  / /   / _ \ | | | | |    | |    | |  | || |__) | |  | | (___  %NC%
echo %CYAN%%BOLD%   \ \/ /   / ___ \| | | | |    | |    | |  | ||  ___/| |  | |\___ \ %NC%
echo %CYAN%%BOLD%    \  /   / /   \ \ |_| | |____| |    | |__| || |    | |__| |____) |%NC%
echo %CYAN%%BOLD%     \/   /_/     \_\____|______|_|     \____/ |_|     \____/|_____/ %NC%
echo.
echo %BLUE%%BOLD%>>> THE INFINITY CLOUD STORAGE PROJECT <<< %NC%
echo.

:: --- 1. Bootstrap Python ---
echo %BLUE%[INFO]%NC% Checking for Python...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo %YELLOW%[WARNING]%NC% Python not found.
    echo %CYAN%[PROMPT]%NC% Would you like to install Python via winget? (y/n)
    set /p install_py=
    if /i "!install_py!"=="y" (
        log_info "Installing Python 3.10..."
        winget install Python.Python.3.10 --silent --accept-package-agreements --accept-source-agreements
        if %errorlevel% neq 0 (
            echo %RED%[ERROR]%NC% Winget install failed. Please install Python manually from python.org.
            pause
            exit /b 1
        )
        :: Refresh path
        refreshenv >nul 2>&1
    ) else (
        echo %RED%[ERROR]%NC% Python is required.
        pause
        exit /b 1
    )
)
echo %GREEN%[SUCCESS]%NC% Python detected.

:: --- 2. Bootstrap Node.js ---
echo %BLUE%[INFO]%NC% Checking for Node.js...
node --version >nul 2>&1
set HAS_NODE=1
if %errorlevel% neq 0 (
    echo %YELLOW%[WARNING]%NC% Node.js not found.
    echo %CYAN%[PROMPT]%NC% Would you like to install Node.js? (y/n)
    set /p install_node=
    if /i "!install_node!"=="y" (
        winget install OpenJS.NodeJS --silent --accept-package-agreements --accept-source-agreements
        refreshenv >nul 2>&1
    ) else (
        set HAS_NODE=0
    )
)

:: --- 3. Virtual Environment & Dependencies ---
if not exist "venv" (
    echo %BLUE%[INFO]%NC% Creating Virtual Environment...
    python -m venv venv
)
echo %BLUE%[INFO]%NC% Activating Virtual Environment...
call venv\Scripts\activate.bat

echo %BLUE%[INFO]%NC% Installing Python dependencies...
pip install -r requirements.txt
if %errorlevel% neq 0 (
    echo %RED%[ERROR]%NC% Failed to install Python dependencies.
    pause
    exit /b 1
)
echo %GREEN%[SUCCESS]%NC% Python dependencies installed.

:: --- 4. Configuration ---
echo.
echo %BOLD%--- Discord Bot Configuration ---%NC%
set /p TOKEN="Enter your Discord Bot Token (leave empty to skip): "
set /p CHANNEL_ID="Enter your Discord Channel ID (leave empty to skip): "

:: Clean up input (strip quotes and commas)
set TOKEN=%TOKEN:"=%
set TOKEN=%TOKEN:,=%
set CHANNEL_ID=%CHANNEL_ID:"=%
set CHANNEL_ID=%CHANNEL_ID:,=%

if not exist "src\config.json" (
    if not exist "src" mkdir src
    echo {"discord": {"token": "", "channel_id": "", "command_prefix": "/"}} > src\config.json
)

:: Use python to update JSON safely
python -c "import json; d=json.load(open('src/config.json')); 
if r'%TOKEN%': d['discord']['token']=r'%TOKEN%'
if r'%CHANNEL_ID%': d['discord']['channel_id']=r'%CHANNEL_ID%'
json.dump(d, open('src/config.json', 'w'), indent=2)"

echo %GREEN%[SUCCESS]%NC% Configuration updated.

:: --- 5. Frontend Setup ---
if %HAS_NODE% equ 1 (
    echo.
    echo %BOLD%--- Frontend Setup ---%NC%
    echo %CYAN%[PROMPT]%NC% Install npm packages for Web & Mobile? (y/n)
    set /p do_npm=
    if /i "!do_npm!"=="y" (
        for %%D in (src\WI\client src\WI\mobile) do (
            if exist "%%D\package.json" (
                echo %BLUE%[INFO]%NC% Running npm install in %%D...
                cd %%D
                call npm install
                cd %~dp0
            )
        )
    )
)

echo.
echo %GREEN%%BOLD%VAULT_OPUS Installation Complete!%NC%
echo Run the app with:
echo   - Backend: venv\Scripts\python.exe src\VAULT_OPUS.py
echo   - Web GUI: venv\Scripts\python.exe src\WI\server.py
echo.
pause
