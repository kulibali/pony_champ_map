@echo off
set TARGET=champ-map

if "%1"=="help" goto usage
if "%1"=="--help" goto usage

where stable > nul
if errorlevel 1 goto nostable
where ponyc > nul
if errorlevel 1 goto noponyc

set GOTOCLEAN=false
if "%1"=="clean" (
  set GOTOCLEAN=true
  shift
)

set GOTOTEST=false
if "%1"=="test" (
  set GOTOTEST=true
  shift
)
set GOTODOCS=false
if "%1"=="docs" (
  set GOTODOCS=true
  shift
)

set CONFIG=release
set DEBUG=
if "%1"=="config" (
  if "%2"=="debug" (
    set CONFIG=debug
    set DEBUG=--debug
  )
  shift
  shift
)

set BUILDDIR=build\%CONFIG%

if "%GOTOCLEAN%"=="true" goto clean
if "%GOTOTEST%"=="true" goto test
if "%GOTODOCS%"=="true" goto docs
if "%1"=="fetch" goto fetch

:build
if not exist "%BUILDDIR%" mkdir "%BUILDDIR%""
if not exist "VERSION" goto noversion
if not exist %TARGET%\version.pony.in goto noversion
set /p VERSION=<VERSION
if exist ".git" for /f %%i in ('git rev-parse --short HEAD') do set "VERSION=%VERSION%-%%i [%CONFIG%]"
if not exist ".git" set "VERSION=%VERSION% [%CONFIG%]"
setlocal enableextensions disabledelayedexpansion
for /f "delims=" %%i in ('type %TARGET%\version.pony.in ^& break ^> %TARGET%\version.pony') do (
  set "line=%%i"
  setlocal enabledelayedexpansion
  >>%TARGET%\version.pony echo(!line:%%%%VERSION%%%%=%VERSION%!
  endlocal
)
:noversion
echo stable env ponyc %DEBUG% -o %BUILDDIR% %TARGET%\test
stable env ponyc %DEBUG% -o %BUILDDIR% %TARGET%\test
if errorlevel 1 goto error
goto done

:fetch
echo stable fetch
stable fetch
if errorlevel 1 goto error
goto done

:test
if not exist %BUILDDIR%\test.exe (
  echo stable env ponyc %DEBUG% -o %BUILDDIR% %TARGET%\test
  stable env ponyc %DEBUG% -o %BUILDDIR% %TARGET%\test
)
if errorlevel 1 goto error
echo %BUILDDIR%\test.exe --sequential
%BUILDDIR%\test.exe --sequential
if errorlevel 1 goto error
goto done

:docs
stable env ponyc --pass=docs --docs-public -o %BUILDDIR% %TARGET%
if errorlevel 1 goto error
goto done

:clean
if exist %BUILDDIR% (
  echo rmdir /s /q %BUILDDIR%
  rmdir /s /q %BUILDDIR%
)
goto done

:usage
echo Usage: make (help^|clean^|build^|test) [config=debug^|release]
goto done

:nostable
echo You need "stable.exe" (from https://github.com/ponylang/pony-stable) in your PATH.
goto error

:noponyc
echo You need "ponyc.exe" (from https://github.com/ponylang/ponyc) in your PATH.
goto error

:error
%COMSPEC% /c exit 1

:done
