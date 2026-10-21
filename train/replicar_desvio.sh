#!/usr/bin/env bash
# Terceira condicao, com a heuristica codificada de forma adequada.
#
# Na tentativa anterior a trajetoria substituia os pontos de referencia, que
# sao normalizados por 60 m - de modo que o deslocamento lateral, unica coisa
# que distingue a trajetoria da linha central, alterava a observacao em apenas
# 2,5%. Aqui ele entra como observacao propria, normalizado pela meia-largura
# da pista, ocupando mais de 40% da faixa.
#
# 27 observacoes passam a 30. Informacao estritamente adicional: os pontos da
# linha central permanecem.
set -u
export PYTHONIOENCODING=utf-8

GODOT="/c/Users/adm/Desktop/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe"
PY="/c/Users/adm/Desktop/godot-rl-ref/.venv/Scripts/python.exe"
PROJ="C:/tcc/projeto-tcc"
SAIDA="C:/tcc/treinos"
TRAJ="C:/tcc/treinos/linha_pista1.csv"
SEMENTES="${*:-0 1 2 3 4 5 6 7}"

for s in $SEMENTES; do
  nome="rld_s$s"
  echo "===== $nome (semente $s)  $(date +%H:%M:%S) ====="
  "$PY" "$PROJ/train/train_sb3.py" --timesteps=300000 --seed="$s" --speedup=20 \
      --experiment_dir="$SAIDA" --experiment_name="$nome" \
      --save_model_path="$SAIDA/$nome" \
      --onnx_export_path="$SAIDA/$nome.onnx" >"$SAIDA/$nome.log" 2>&1 &
  pid=$!
  t=0
  until netstat -an 2>/dev/null | grep -q "11008.*LISTENING" || [ $t -ge 60 ]; do sleep 1; t=$((t+1)); done
  "$GODOT" --headless --path "$PROJ" --modo=training --fixed-fps 2000 \
      --disable-render-loop --linha_desvio="$TRAJ" \
      --voltas="$SAIDA/${nome}_voltas.csv" >/dev/null 2>&1
  wait $pid
  echo "  concluido $(date +%H:%M:%S)"
done
echo "TODAS AS EXECUCOES CONCLUIDAS"
