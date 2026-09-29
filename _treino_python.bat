@echo off
REM Chamado por treinar.bat numa janela separada. Nao execute direto.
REM Argumentos: %1 passos  %2 semente  %3 nome  %4 frequencia de checkpoint
set PY=C:\Users\adm\Desktop\godot-rl-ref\.venv\Scripts\python.exe
set PROJ=C:\tcc\projeto-tcc
set SAIDA=C:\tcc\treinos
"%PY%" "%PROJ%\train\train_sb3.py" --timesteps=%1 --seed=%2 --speedup=20 --save_checkpoint_frequency=%4 --experiment_dir="%SAIDA%" --experiment_name=%3 --save_model_path="%SAIDA%\%3" --onnx_export_path="%SAIDA%\%3.onnx"
echo.
echo   treino encerrado. Feche esta janela quando quiser.
