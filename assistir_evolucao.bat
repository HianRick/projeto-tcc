@echo off
setlocal enabledelayedexpansion
REM ===================================================================
REM  Percorre os checkpoints de um treino, do mais novo ao mais velho,
REM  abrindo o simulador em cada um. Mostra o aprendizado evoluindo.
REM
REM    assistir_evolucao.bat <nome-da-execucao>
REM
REM  Feche a janela do simulador para passar ao proximo checkpoint.
REM ===================================================================
set PY=C:\Users\adm\Desktop\godot-rl-ref\.venv\Scripts\python.exe
set GODOT=C:\Users\adm\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe
set PROJ=C:\tcc\projeto-tcc
set SAIDA=C:\tcc\treinos

set NOME=%~1
if "%NOME%"=="" (
  echo   informe a execucao, ex:  assistir_evolucao.bat m2_seed0
  exit /b 1
)

if not exist "%SAIDA%\%NOME%_evolucao" (
  echo   convertendo os checkpoints para ONNX...
  "%PY%" "%PROJ%\train\exportar_checkpoints.py" "%SAIDA%" %NOME%
  if errorlevel 1 exit /b 1
)

echo.
for %%F in ("%SAIDA%\%NOME%_evolucao\*.onnx") do (
  echo   ============================================
  echo    %%~nF
  echo   ============================================
  copy /y "%%F" "%PROJ%\model.onnx" >nul
  "%GODOT%" --path "%PROJ%" --modo=inference --assistir
)
echo.
echo   fim da evolucao.
endlocal
