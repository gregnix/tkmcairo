@echo off
REM ==========================================================================
REM demo-win.bat — run a tkmcairo demo under BAWT
REM
REM Usage:
REM     demo-win.bat 86 surface
REM     demo-win.bat 86 plot
REM     demo-win.bat 86 plot-y2
REM     demo-win.bat 86 imageviewer
REM     demo-win.bat 86 chan-export
REM     demo-win.bat 86 svgview
REM     demo-win.bat 86 pageview
REM     demo-win.bat 86 viewport
REM     demo-win.bat 86 scene
REM     demo-win.bat 86 axis
REM
REM First arg is BAWT version (86 or 90), second is the demo name.
REM ==========================================================================

setlocal EnableDelayedExpansion

set TCL_VER=86
if not "%~1"=="" set TCL_VER=%~1

set NAME=%~2
if "%NAME%"=="" (
    echo Usage: demo-win.bat ^<86^|90^> ^<demo-name^>
    echo.
    echo Available demos:
    for %%f in (demos\demo-*.tcl) do echo     %%~nf
    exit /b 1
)

REM Strip optional "demo-" prefix from user input
if "%NAME:~0,5%"=="demo-" set NAME=%NAME:~5%

set DEMO=demos\demo-%NAME%.tcl
if not exist "%DEMO%" (
    echo Demo not found: %DEMO%
    echo.
    echo Available demos:
    for %%f in (demos\demo-*.tcl) do echo     %%~nf
    exit /b 1
)

REM Locate wish + tclmcairo — try C:\Tcl first, then BAWT
set WISH=
set TCL_LIB=

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

set BAWT_DIR=C:\Bawt\Bawt%TCL_VER%
if exist "%BAWT_DIR%\Windows\x64\Development\opt\Tcl\bin\wish.exe" (
    set WISH=%BAWT_DIR%\Windows\x64\Development\opt\Tcl\bin\wish.exe
    set TCL_LIB=%BAWT_DIR%\Windows\x64\Development\opt\Tcl\lib
    goto :wish_found
)

:wish_found
if "%WISH%"=="" (
    echo Cannot find wish.exe in C:\Tcl or BAWT
    exit /b 1
)

set TCLMCAIRO_LIBDIR=
for /D %%d in ("%TCL_LIB%\tclmcairo*") do set TCLMCAIRO_LIBDIR=%%d

if "%TCLMCAIRO_LIBDIR%"=="" (
    echo No tclmcairo* found in %TCL_LIB%
    exit /b 1
)

set TCLMCAIRO_LIBDIR=%TCLMCAIRO_LIBDIR%
"%WISH%" "%DEMO%"

endlocal
