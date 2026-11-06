@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0hs80-rgb.ps1" %*
set "result=%errorlevel%"
if not "%result%"=="0" (
    echo.
    echo HS80 RGB: falha. Veja a mensagem acima.
    pause
)
exit /b %result%
