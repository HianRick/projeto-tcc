@echo off
setlocal enabledelayedexpansion
REM ===================================================================
REM  Dirija voce mesmo, no teclado.
REM
REM    dirigir.bat [pista] [flags...]
REM
REM  Exemplos:
REM    dirigir.bat                            pista original
REM    dirigir.bat --sensores                 pista original, com os raios
REM    dirigir.bat interlagos_reduzido        Interlagos a 25%%
REM    dirigir.bat interlagos_reduzido --sensores --assistir
REM
REM  As voltas sao cronometradas e gravadas em
REM  C:\tcc\treinos\humano_<pista>.csv
REM
REM  Controles:  W acelera  S freia/re  A e D esterco  R reinicia
REM              --sensores desenha os raios do sensor de parede
REM              --assistir usa a camera livre em vez da camera do carro
REM ===================================================================
set GODOT=C:\Users\adm\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe
set PROJ=C:\tcc\projeto-tcc
set SAIDA=C:\tcc\treinos

REM  O primeiro argumento so e nome de pista se nao comecar com "--".
REM  O resto e repassado intacto: uso %* porque o cmd quebra tokens no "=",
REM  e um %~2 perderia o valor de flags como --linha=caminho.csv
set "ARG1=%~1"
set "TODOS=%*"
set "NOME="
set "EXTRA=%TODOS%"
if not "%ARG1%"=="" (
  if not "!ARG1:~0,2!"=="--" (
    set "NOME=%ARG1%"
    set "EXTRA=!TODOS:*%ARG1%=!"
  )
)

if "%NOME%"=="" (
  set "PISTA="
  set "CSV=%SAIDA%\humano_pista1.csv"
) else (
  if not exist "%PROJ%\pistas\%NOME%.tres" (
    echo   nao encontrei a pista "%NOME%"
    echo   disponiveis:
    for %%F in ("%PROJ%\pistas\*.tres") do echo      %%~nF
    echo      ^(sem argumento^) = pista original
    exit /b 1
  )
  set "PISTA=--pista=%NOME%"
  set "CSV=%SAIDA%\humano_%NOME%.csv"
)

if not exist "%SAIDA%" mkdir "%SAIDA%"

echo.
if "%NOME%"=="" (echo   pista:    original) else (echo   pista:    %NOME%)
echo   voltas:   !CSV!
if not "%EXTRA%"=="" echo   extras:  %EXTRA%
echo.
echo   W acelera   S freia/re   A e D esterco   R reinicia
echo   feche a janela quando terminar
echo.

"%GODOT%" --path "%PROJ%" --modo=test_drive !PISTA! !EXTRA! --voltas="!CSV!"

echo.
if exist "!CSV!" (
  echo   suas voltas:
  type "!CSV!"
)
endlocal
