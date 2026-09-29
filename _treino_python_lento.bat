@echo off
REM Chamado por treinar_assistindo.bat. Speedup baixo para dar para acompanhar.
set PY=C:\Users\adm\Desktop\godot-rl-ref\.venv\Scripts\python.exe
set PROJ=C:\tcc\projeto-tcc
set SAIDA=C:\tcc\treinos
"%PY%" "%PROJ%\train\train_sb3.py" --timesteps=%1 --seed=%2 --speedup=1 --experiment_dir="%SAIDA%" --experiment_name=%3 --save_model_path="%SAIDA%\%3" --onnx_export_path="%SAIDA%\%3.onnx"
echo.
echo   treino encerrado. Feche esta janela quando quiser.
