@echo off
rem ============================================================
rem  run_xsim.bat  -  Vivado xsim regression: 12 testbenches
rem
rem  Usage:
rem    run_xsim.bat              -> run all 12 tbs (default)
rem    run_xsim.bat tb_gptp_tc   -> run one tb
rem
rem  Flow: xvlog (compile) -> xelab -a (elaborate + standalone
rem  axsim.exe) -> run to $finish.  axsim.exe auto-exits, so
rem  no GUI hang.  Log written to vivado_proj/run_auto.log.
rem ============================================================
setlocal enabledelayedexpansion
set VIV=C:\Xilinx\Vivado\2018.3
set TB=%~1
if "%TB%"=="" set TB=all

rem ---- Vivado install (edit here if different) ----
if not exist "%VIV%\settings64.bat" (
    echo [ERROR] Vivado not found at %VIV%
    echo         Edit VIV at the top of this file.
    exit /b 1
)
echo [info] Using Vivado at: %VIV%

rem ---- environment ----
call "%VIV%\settings64.bat" >nul 2>&1
rem ensure bin+lib on PATH even if settings64 chain fails
set "PATH=%VIV%\bin;%VIV%\lib\win64.o;%PATH%"
set "XILINX_VIVADO=%VIV%"
set "XILINX_WEBTALK=disable"

rem ---- cd to project root (one level above tools\) ----
cd /d "%~dp0.."
if not exist src\um (
    echo [ERROR] src\um not found under %CD%
    exit /b 1
)

set LOG=vivado_proj\run_auto.log
del "%LOG%" 2>nul

rem ---- compile all RTL + TB once ----
echo [xvlog] compiling src\um + tb ... >> "%LOG%"
for %%f in (src\um\*.v tb\*.v) do (
    call xvlog -sv -i src\um "%%f" >> "%LOG%" 2>&1
    if errorlevel 1 ( echo [ERROR] xvlog failed on %%f & exit /b 1 )
)
echo [xvlog] compile OK >> "%LOG%"

set TBS=tb_gptp_phc tb_gptp_htsu tb_gptp_tc tb_gptp_pdelay tb_gptp_mac_glue tb_gptp_frame_parser tb_gptp_bmca tb_gptp_servo tb_gptp_top tb_gptp_switch tb_gptp_cascade tb_gptp_mac_adapt

if /i "%TB%"=="all" (
    for %%t in (%TBS%) do call :run_one %%t
) else (
    call :run_one %TB%
)

echo. >> "%LOG%"
echo ===================== >> "%LOG%"
echo  FINAL: see PASS/FAIL above >> "%LOG%"
echo ===================== >> "%LOG%"
type "%LOG%"
exit /b 0

:run_one
set NAME=%~1
echo. >> "%LOG%"
echo ===== xelab -a %NAME% ===== >> "%LOG%"
call xelab -a %NAME% -s %NAME%_sim >> "%LOG%" 2>&1
if errorlevel 1 (
    echo [FAIL] %NAME% xelab error >> "%LOG%"
    exit /b 0
)
echo  running %NAME% (axsim) ... >> "%LOG%"
call "xsim.dir\%NAME%_sim\axsim.exe" >> "%LOG%" 2>&1
echo [DONE] %NAME% rc=%errorlevel% >> "%LOG%"
exit /b 0
