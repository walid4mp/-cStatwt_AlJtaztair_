@echo off
setlocal
set "GRADLE_VERSION=8.14"
set "DIST=gradle-%GRADLE_VERSION%-bin"
if "%GRADLE_USER_HOME%"=="" set "GRADLE_USER_HOME=%USERPROFILE%\.gradle"
set "BASE=%GRADLE_USER_HOME%\wrapper\dists\%DIST%"
set "ZIP=%BASE%\%DIST%.zip"
set "DIR=%BASE%\%DIST%"
if not exist "%DIR%\bin\gradle.bat" (
  if not exist "%BASE%" mkdir "%BASE%"
  if not exist "%ZIP%" powershell -NoProfile -Command "Invoke-WebRequest -UseBasicParsing 'https://services.gradle.org/distributions/%DIST%.zip' -OutFile '%ZIP%'"
  if exist "%DIR%" rmdir /s /q "%DIR%"
  powershell -NoProfile -Command "Expand-Archive -Force '%ZIP%' '%BASE%\extract'"
  move "%BASE%\extract\gradle-%GRADLE_VERSION%" "%DIR%" >nul
  rmdir /s /q "%BASE%\extract"
)
call "%DIR%\bin\gradle.bat" %*
