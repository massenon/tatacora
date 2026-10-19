@echo off
rem ===========================================================================
rem  TATACORA - Systeme de gestion Integre : construction de l'installateur
rem  Windows (TATACORA_Setup_<version>.exe).
rem
rem  A lancer depuis une invite de commandes, dans le dossier tatacora-flutter :
rem      build_windows.bat              (build de production, ENV=production)
rem      build_windows.bat recette      (autre flavor : dev, recette)
rem
rem  Etapes, chacune ARRETE le script en cas d'echec :
rem    1. flutter pub get
rem    2. dart run build_runner build --delete-conflicting-outputs  (code Drift)
rem    3. flutter build windows --release -t lib\main.dart  (JAMAIS main_demo)
rem    4. Inno Setup 6 (ISCC.exe) compile installer\tatacora.iss
rem
rem  Prerequis : voir README_DEPLOY.md.
rem ===========================================================================

setlocal EnableExtensions

rem Le script travaille depuis SON dossier, d'ou qu'on l'appelle.
cd /d "%~dp0"

set "TATACORA_ENV=%~1"
if "%TATACORA_ENV%"=="" set "TATACORA_ENV=production"
rem La demonstration a son propre point d'entree (lib\main_demo.dart) : elle
rem ne s'installe pas chez le client.
if /i "%TATACORA_ENV%"=="demo" (
  echo [ERREUR] Le flavor "demo" ne se package pas : lib\main.dart seulement.
  goto :erreur
)

rem --- Version lue dans pubspec.yaml (ligne "version: 1.0.0+1") -------------
set "VERSION_COMPLETE="
for /f "tokens=2 delims=: " %%v in ('findstr /b /c:"version:" pubspec.yaml') do set "VERSION_COMPLETE=%%v"
if "%VERSION_COMPLETE%"=="" (
  echo [ERREUR] Version introuvable dans pubspec.yaml ^(ligne "version:"^).
  goto :erreur
)
for /f "tokens=1 delims=+" %%a in ("%VERSION_COMPLETE%") do set "APP_VERSION=%%a"

echo.
echo === TATACORA %APP_VERSION% (%VERSION_COMPLETE%) - flavor %TATACORA_ENV% ===
echo.

rem --- Outils requis ------------------------------------------------------------
where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERREUR] La commande "flutter" est introuvable. Installez Flutter et
  echo          ajoutez son dossier bin au PATH ^(voir README_DEPLOY.md^).
  goto :erreur
)

set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not defined ISCC if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not defined ISCC for /f "delims=" %%i in ('where ISCC.exe 2^>nul') do if not defined ISCC set "ISCC=%%i"
if not defined ISCC (
  echo [ERREUR] Inno Setup 6 est introuvable ^(ISCC.exe^).
  echo          Installez-le depuis https://jrsoftware.org/isdl.php ^(Inno Setup 6^),
  echo          dans son dossier par defaut, puis relancez ce script.
  goto :erreur
)
echo Inno Setup : %ISCC%

rem --- 1. Dependances -----------------------------------------------------------
echo.
echo [1/4] flutter pub get
call flutter pub get
if errorlevel 1 goto :erreur

rem --- 2. Code genere (Drift) ---------------------------------------------------
echo.
echo [2/4] dart run build_runner build --delete-conflicting-outputs
call dart run build_runner build --delete-conflicting-outputs
if errorlevel 1 goto :erreur

rem --- 3. Application Windows (point d'entree de PRODUCTION) --------------------
echo.
echo [3/4] flutter build windows --release -t lib\main.dart --dart-define=ENV=%TATACORA_ENV%
call flutter build windows --release -t lib\main.dart --dart-define=ENV=%TATACORA_ENV%
if errorlevel 1 goto :erreur

if not exist "build\windows\x64\runner\Release\tatacora_flutter.exe" (
  echo [ERREUR] build\windows\x64\runner\Release\tatacora_flutter.exe est absent.
  goto :erreur
)

rem --- 4. Installateur -----------------------------------------------------------
echo.
echo [4/4] Inno Setup : installer\tatacora.iss
"%ISCC%" /DAppVersion=%APP_VERSION% "installer\tatacora.iss"
if errorlevel 1 goto :erreur

echo.
echo === Termine : build\installer\TATACORA_Setup_%APP_VERSION%.exe ===
endlocal
exit /b 0

:erreur
echo.
echo === ECHEC de la construction : voir le message ci-dessus. ===
endlocal
exit /b 1
