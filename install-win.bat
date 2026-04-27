@echo off
REM ==========================================================================
REM install-win.bat — install tkmcairo under Windows
REM
REM tkmcairo is pure Tcl — no C compilation needed. This script just copies
REM the .tm modules and pkgIndex.tcl to the Tcl library directory so
REM "package require tkmcairo::*" finds them.
REM
REM Usage:
REM     install-win.bat        86            (BAWT 8.6 default)
REM     install-win.bat        90            (BAWT 9.0)
REM     install-win.bat        86 C:\MyTcl   (custom Tcl install)
REM
REM Output: <TCL_LIB>\tkmcairo0.1.1\
REM ==========================================================================

setlocal EnableDelayedExpansion

set VERSION=0.1.1

REM Default Tcl version
set TCL_VER=86
if not "%~1"=="" set TCL_VER=%~1

REM --------------------------------------------------------------------------
REM Locate Tcl install
REM
REM Search order:
REM   1. Explicit second argument (highest priority)
REM   2. C:\Tcl\lib  (standard for ActiveTcl / Magicsplat / manual installs)
REM   3. BAWT default at C:\Bawt\Bawt%TCL_VER%\Windows\x64\...
REM
REM The script picks the FIRST directory it finds. Override with arg 2.
REM --------------------------------------------------------------------------
set TCL_ROOT=
if not "%~2"=="" (
    set TCL_ROOT=%~2
    goto :tcl_found
)

REM Try C:\Tcl\lib first — most common standalone install
if exist "C:\Tcl\lib" (
    set TCL_ROOT=C:\Tcl
    goto :tcl_found
)

REM Try BAWT
set BAWT_DIR=C:\Bawt\Bawt%TCL_VER%
if exist "!BAWT_DIR!\Windows\x64\Development\opt\Tcl\lib" (
    set TCL_ROOT=!BAWT_DIR!\Windows\x64\Development\opt\Tcl
    goto :tcl_found
)

:tcl_found
if "%TCL_ROOT%"=="" (
    echo Cannot locate Tcl install. Pass it as second argument:
    echo     install-win.bat %TCL_VER% C:\path\to\Tcl
    echo.
    echo Looked for:
    echo     C:\Tcl                                                     ^(standard^)
    echo     C:\Bawt\Bawt%TCL_VER%\Windows\x64\Development\opt\Tcl      ^(BAWT^)
    exit /b 1
)

set TCL_LIB=%TCL_ROOT%\lib
if not exist "%TCL_LIB%" (
    echo TCL_LIB does not exist: %TCL_LIB%
    exit /b 1
)

REM --------------------------------------------------------------------------
REM Sanity check — tclmcairo must already be installed
REM --------------------------------------------------------------------------
set TCLMCAIRO_FOUND=0
for /D %%d in ("%TCL_LIB%\tclmcairo*") do (
    set TCLMCAIRO_FOUND=1
    echo Found dependency: %%d
)
if "%TCLMCAIRO_FOUND%"=="0" (
    echo.
    echo Warning: no tclmcairo* found in %TCL_LIB%
    echo tkmcairo needs tclmcairo 0.3.5 or newer.
    echo Install tclmcairo first using its build-win.bat.
    echo.
    set /p CONTINUE=Continue anyway? [y/N]: 
    if /I not "!CONTINUE!"=="y" exit /b 1
)

REM --------------------------------------------------------------------------
REM Install
REM --------------------------------------------------------------------------
set DEST=%TCL_LIB%\tkmcairo%VERSION%

echo === tkmcairo %VERSION% =================================================
echo Tcl install:  %TCL_ROOT%
echo Target:       %DEST%
echo.

if exist "%DEST%" (
    echo Removing old install at %DEST% ...
    rmdir /s /q "%DEST%"
)

mkdir "%DEST%"
mkdir "%DEST%\tkmcairo"

REM Copy pkgIndex
copy /Y "tcl\pkgIndex.tcl" "%DEST%\pkgIndex.tcl" >nul
if errorlevel 1 (
    echo Failed to copy pkgIndex.tcl
    exit /b 1
)
echo OK: pkgIndex.tcl

REM Copy all .tm modules
copy /Y "tcl\tkmcairo\*.tm" "%DEST%\tkmcairo\" >nul
if errorlevel 1 (
    echo Failed to copy .tm modules
    exit /b 1
)

REM Count modules installed
set N=0
for %%f in ("%DEST%\tkmcairo\*.tm") do set /a N+=1
echo OK: %N% .tm modules

REM Copy LICENSE
if exist LICENSE copy /Y LICENSE "%DEST%\LICENSE" >nul

echo.
echo === Installation done ==================================================
echo Installed to: %DEST%
echo.
echo Test:
echo     test-win.bat %TCL_VER%
echo.
echo Or in any Tcl shell:
echo     package require tkmcairo::surface
echo     package require tkmcairo::imageviewer

endlocal
