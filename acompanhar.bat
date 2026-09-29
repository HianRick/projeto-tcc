@echo off
REM ===================================================================
REM  Abre o TensorBoard com as curvas de todas as execucoes.
REM  Depois de rodar, abra no navegador:  http://localhost:6006
REM ===================================================================
set TB=C:\Users\adm\Desktop\godot-rl-ref\.venv\Scripts\tensorboard.exe
echo.
echo   TensorBoard em http://localhost:6006
echo   (Ctrl+C para encerrar)
echo.
"%TB%" --logdir C:\tcc\treinos --port 6006
