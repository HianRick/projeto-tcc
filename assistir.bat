@echo off
setlocal
REM ===================================================================
REM  Assiste ao agente treinado dirigindo.
REM
REM    assistir.bat <nome-da-execucao> [--assistir]
REM
REM  Com --assistir, sobe a camera livre em vez da camera do carro.
REM
REM  Converte o modelo para arquivo unico e roda o simulador com janela.
REM ===================================================================
set PY=C:\Users\adm\Desktop\godot-rl-ref\.venv\Scripts\python.exe
set GODOT=C:\Users\adm\Desktop\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe
set PROJ=C:\tcc\projeto-tcc
set SAIDA=C:\tcc\treinos

set NOME=%~1
if "%NOME%"=="" (
  echo   informe o nome da execucao, ex:  assistir.bat m2_seed0
  exit /b 1
)
if not exist "%SAIDA%\%NOME%.onnx" (
  echo   nao encontrei "%SAIDA%\%NOME%.onnx"
  exit /b 1
)

echo   convertendo o modelo para arquivo unico...
"%PY%" "%PROJ%\train\onnx_arquivo_unico.py" "%SAIDA%\%NOME%.onnx" "%PROJ%\model.onnx"
if errorlevel 1 exit /b 1

echo   abrindo o simulador...
"%GODOT%" --path "%PROJ%" --modo=inference %~2
endlocal
