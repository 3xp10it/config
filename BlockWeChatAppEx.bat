@echo off
chcp 65001 >nul 2>&1
title Block WeChatAppEx - SRP toggle (needs admin)

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo.
  echo [ERROR] Please run as Administrator!
  echo   Right-click this file - Run as administrator
  echo.
  pause
  exit /b 1
)

set "RULE={A7C3E91F-5B62-4D8A-9E17-3F2C8B4D6A05}"
set "SRP=HKLM\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
set "DISALLOWED=%SRP%\0"
set "PATHS=%DISALLOWED%\Paths"
set "TARGET=C:\Users\Administrator\AppData\Roaming\Tencent\xwechat\xplugin\plugins\RadiumWMPF\WeChatAppEx.exe"

:menu
cls
echo ============================================
echo   Block WeChatAppEx (Software Restriction)
echo ============================================
echo.
echo   Target: %TARGET%
echo.
echo   Effect: Stops WeChatAppEx from running.
echo   WeChat chat still works; Mini Programs /
echo   Channels / Official Accounts won't open.
echo   Requires SIGN OUT or REBOOT to take effect.
echo.
echo   [1] BLOCK  (add SRP deny rule)
echo   [2] UNBLOCK (remove rule, restore)
echo   [3] SHOW STATUS
echo   [4] Exit
echo.
set /p c=Select (1-4): 
if "%c%"=="1" goto block
if "%c%"=="2" goto unblock
if "%c%"=="3" goto status
if "%c%"=="4" exit
goto menu

:block
echo.
echo Adding deny rule...
reg add "%SRP%" /v DefaultLevel /t REG_DWORD /d 262144 /f >nul 2>&1
reg add "%SRP%" /v TransparentEnabled /t REG_DWORD /d 1 /f >nul 2>&1
reg add "%SRP%" /v PolicyScope /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%DISALLOWED%" /ve /f >nul 2>&1
reg add "%PATHS%" /ve /f >nul 2>&1
reg add "%PATHS%\%RULE%" /v "ItemData" /t REG_SZ /d "%TARGET%" /f >nul 2>&1
reg add "%PATHS%\%RULE%" /v "SaferFlags" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%PATHS%\%RULE%" /v "descriptor" /t REG_SZ /d "Block WeChatAppEx.exe (mini-program engine)" /f >nul 2>&1

echo.
echo DONE. Now SIGN OUT or REBOOT, then open WeChat.
echo WeChat memory should drop from ~1.6GB to ~400MB.
echo.
pause
goto menu

:unblock
echo.
echo Removing deny rule...
reg delete "%PATHS%\%RULE%" /f >nul 2>&1
echo DONE. Sign out or reboot to fully restore.
echo.
pause
goto menu

:status
echo.
echo --- SRP paths rules ---
reg query "%PATHS%" 2>nul | findstr /i "A7C3E91F WeChatAppEx"
echo.
echo --- Target file exists? ---
if exist "%TARGET%" (echo   YES) else (echo   NO - path changed, update TARGET in this script)
echo.
pause
goto menu
