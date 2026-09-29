@echo off
setlocal
REM ===================================================================
REM  Igual ao treinar.bat, mas com janela e camera livre.
REM  Bem mais lento: use para observar, nao para treinar de verdade.
REM
REM    treinar_assistindo.bat <nome> [passos] [semente]
REM
REM  Camera: SETAS olham | WASD move | Q/E desce e sobe
REM          Shift acelera | Tab segue um carro | 1-9 escolhe qual
REM
REM  Use as setas para olhar. O mouse falha durante o treino porque a
REM  engine fica bloqueada esperando o Python e perde os eventos.
REM ===================================================================
set GODOT=C:\Users\adm\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe
set PROJ=C:\tcc\projeto-tcc
set SAIDA=C:\tcc\treinos

set NOME=%~1
if "%NOME%"=="" set NOME=observando
set PASSOS=%~2
if "%PASSOS%"=="" set PASSOS=100000
set SEMENTE=%~3
if "%SEMENTE%"=="" set SEMENTE=0

if not exist "%SAIDA%" mkdir "%SAIDA%"

echo.
echo   execucao: %NOME%   passos: %PASSOS%
echo   MODO OBSERVACAO - com janela, velocidade reduzida
echo.
echo   SETAS olham ^| WASD move ^| Q/E desce e sobe
echo   Shift acelera ^| Tab segue um carro ^| 1-9 escolhe qual
echo.
echo   [1/2] subindo o lado Python...
start "Treino Python - %NOME%" "%PROJ%\_treino_python_lento.bat" %PASSOS% %SEMENTE% %NOME%

echo   aguardando o servidor abrir...
timeout /t 6 /nobreak >nul

echo   [2/2] abrindo o simulador...
"%GODOT%" --path "%PROJ%" --modo=training --assistir --carros=4 --voltas="%SAIDA%\%NOME%_voltas.csv"

echo.
echo   encerrado.
endlocal
