@echo off
setlocal
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo Visual Studio 2022 with C++ tools is required.
  exit /b 1
)
for /f "usebackq delims=" %%V in (`"%VSWHERE%" -latest -products * -property installationPath`) do set "VSROOT=%%V"
if not defined VSROOT exit /b 1
call "%VSROOT%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
pushd "%~dp0" || exit /b 1
cl /nologo /std:c++20 /EHsc /O2 /MT /Fe:capture-window.exe capture-window.cpp d3d11.lib dxgi.lib windowsapp.lib windowscodecs.lib runtimeobject.lib ole32.lib user32.lib gdi32.lib
set "RESULT=%ERRORLEVEL%"
popd
exit /b %RESULT%
