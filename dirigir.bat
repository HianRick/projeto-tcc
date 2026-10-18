@echo off
setlocal
REM ===================================================================
REM  Dirija voce mesmo, no teclado.
REM
REM    dirigir.bat                      pista original
REM    dirigir.bat interlagos           Interlagos em escala real (4,3 km)
REM    dirigir.bat interlagos_reduzido  Interlagos a 25% (1,1 km)
REM
REM  As voltas sao cronometradas e gravadas em
REM  C:\tcc\treinos\humano_<pista>.csv
REM
REM  Controles:  W acelera  S freia/re  A e D esterco  R reinicia
REM ===================================================================
set GODOT=C:\Users\adm\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe
set PROJ=C:\tcc\projeto-tcc
set SAIDA=C:\tcc\treinos

set NOME=%~1
if "%NOME%"=="" (
  set PISTA=
  set CSV=%SAIDA%\humano_pista1.csv
) else (
  if not exist "%PROJ%\pistas\%NOME%.tres" (
    echo   nao encontrei a pista "%NOME%"
    echo   disponiveis:
    for %%F in ("%PROJ%\pistas\*.tres") do echo      %%~nF
    echo      ^(sem argumento^) = pista original
    exit /b 1
  )
  set PISTA=--pista=%NOME%
  set CSV=%SAIDA%\humano_%NOME%.csv
)

if not exist "%SAIDA%" mkdir "%SAIDA%"

echo.
echo   pista:    %NOME% ^(vazio = original^)
echo   voltas:   %CSV%
echo.
echo   W acelera   S freia/re   A e D esterco   R reinicia
echo   feche a janela quando terminar
echo.

"%GODOT%" --path "%PROJ%" --modo=test_drive %PISTA% --voltas="%CSV%"

echo.
if exist "%CSV%" (
  echo   suas voltas:
  type "%CSV%"
)
endlocal
