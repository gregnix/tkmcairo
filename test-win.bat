@echo off
REM ==========================================================================
REM test-win.bat — run tkmcairo test suite under Windows BAWT
REM
REM Usage:
REM     test-win.bat 86       (BAWT Tcl 8.6, default)
REM     test-win.bat 90       (BAWT Tcl 9.0)
REM ==========================================================================

setlocal EnableDelayedExpansion

set TCL_VER=86
if not "%~1"=="" set TCL_VER=%~1

REM Locate wish — try standard locations first, then BAWT
set WISH=
set TCL_LIB=

REM 1. C:\Tcl
if exist "C:\Tcl\bin\wish.exe" (
    set WISH=C:\Tcl\bin\wish.exe
    set TCL_LIB=C:\Tcl\lib
    goto :wish_found
)
if exist "C:\Tcl\bin\wish%TCL_VER%.exe" (
    set WISH=C:\Tcl\bin\wish%TCL_VER%.exe
    set TCL_LIB=C:\Tcl\lib
    goto :wish_found
)

REM 2. BAWT
set BAWT_DIR=C:\Bawt\Bawt%TCL_VER%
if exist "%BAWT_DIR%\Windows\x64\Development\opt\Tcl\bin\wish.exe" (
    set WISH=%BAWT_DIR%\Windows\x64\Development\opt\Tcl\bin\wish.exe
    set TCL_LIB=%BAWT_DIR%\Windows\x64\Development\opt\Tcl\lib
    goto :wish_found
)

:wish_found
if "%WISH%"=="" (
    echo Cannot find wish.exe. Looked for:
    echo     C:\Tcl\bin\wish.exe
    echo     C:\Tcl\bin\wish%TCL_VER%.exe
    echo     C:\Bawt\Bawt%TCL_VER%\Windows\x64\Development\opt\Tcl\bin\wish.exe
    exit /b 1
)

REM Locate tclmcairo install (the test suite needs it via TCLMCAIRO_LIBDIR)
set TCLMCAIRO_LIBDIR=
for /D %%d in ("%TCL_LIB%\tclmcairo*") do set TCLMCAIRO_LIBDIR=%%d

if "%TCLMCAIRO_LIBDIR%"=="" (
    echo No tclmcairo* found in %TCL_LIB%
    echo Install tclmcairo first.
    exit /b 1
)

echo === tkmcairo test suite ===============================================
echo wish:              %WISH%
echo TCLMCAIRO_LIBDIR:  %TCLMCAIRO_LIBDIR%
echo.

set TCLMCAIRO_LIBDIR=%TCLMCAIRO_LIBDIR%
"%WISH%" tests\test-tkmcairo.tcl

endlocal
