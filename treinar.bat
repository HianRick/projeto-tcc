@echo off
setlocal
REM ===================================================================
REM  Treina o agente. Abre o Python numa janela e o simulador nesta.
REM
REM    treinar.bat <nome-da-execucao> [passos] [semente] [trajetoria.csv]
REM
REM  Com o quarto argumento, os pontos de referencia entregues ao agente
REM  passam a vir da trajetoria calculada em vez da linha central. E a
REM  condicao experimental de RL com heuristica.
REM
REM  Salva um checkpoint a cada 1/10 do treino, para depois assistir a
REM  evolucao com exportar_checkpoints.py + assistir_evolucao.bat
REM
REM  Exemplo:  treinar.bat m2_seed0 300000 0
REM ===================================================================
set GODOT=C:\Users\adm\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe
set PROJ=C:\tcc\projeto-tcc
set SAIDA=C:\tcc\treinos

set NOME=%~1
if "%NOME%"=="" set NOME=teste
set PASSOS=%~2
if "%PASSOS%"=="" set PASSOS=300000
set SEMENTE=%~3
if "%SEMENTE%"=="" set SEMENTE=0
set TRAJ=%~4
if "%TRAJ%"=="" (set OBS=) else (set OBS=--linha_obs=%TRAJ%)

REM um checkpoint a cada decimo do treino
set /a CHECK=%PASSOS%/10

if not exist "%SAIDA%" mkdir "%SAIDA%"

echo.
echo   execucao: %NOME%   passos: %PASSOS%   semente: %SEMENTE%
if not "%TRAJ%"=="" echo   observacoes a partir de: %TRAJ%
echo   checkpoint a cada %CHECK% passos
echo   saida:    %SAIDA%
echo.
echo   [1/2] subindo o lado Python...
start "Treino Python - %NOME%" "%PROJ%\_treino_python.bat" %PASSOS% %SEMENTE% %NOME% %CHECK%

echo   aguardando o servidor abrir...
timeout /t 6 /nobreak >nul

echo   [2/2] iniciando o simulador...
echo.
"%GODOT%" --headless --path "%PROJ%" --modo=training --fixed-fps 2000 --disable-render-loop %OBS% --voltas="%SAIDA%\%NOME%_voltas.csv"

echo.
echo   simulador encerrado. Veja o resultado na janela do Python.
endlocal
