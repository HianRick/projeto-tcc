#!/usr/bin/env bash
# Ablacao do cone do sensor.
#
# Treina tres sementes de Aprendizado por Reforco puro com os mesmos 17 raios
# e o mesmo alcance de 45 m, alterando apenas a abertura angular: de 360 graus,
# herdados do exemplo de origem, para 150 graus concentrados a frente.
#
# O passo entre raios vizinhos cai de 21,2 para 8,8 graus, e o vao entre eles
# a vinte metros encolhe de 7,3 m para 3,1 m - contra 9 m de largura de pista.
#
# Tudo o mais permanece identico as execucoes rl_s0..2, de modo que a
# comparacao seja atribuivel a distribuicao angular dos raios.
set -u

# Sem isto, a excecao de codificacao na exportacao do ONNX derruba o
# salvamento do modelo junto, descartando o treino inteiro.
export PYTHONIOENCODING=utf-8

GODOT="/c/Users/adm/Desktop/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe"
PY="/c/Users/adm/Desktop/godot-rl-ref/.venv/Scripts/python.exe"
PROJ="C:/tcc/projeto-tcc"
SAIDA="C:/tcc/treinos"
PASSOS=300000
CONE=150

for s in 0 1 2; do
  nome="rlc_s$s"
  echo "=============================================================="
  echo " $nome   (semente $s, cone $CONE graus)   $(date +%H:%M:%S)"
  echo "=============================================================="

  "$PY" "$PROJ/train/train_sb3.py" \
      --timesteps=$PASSOS --seed="$s" --speedup=20 \
      --experiment_dir="$SAIDA" --experiment_name="$nome" \
      --save_model_path="$SAIDA/$nome" \
      --onnx_export_path="$SAIDA/$nome.onnx" >"$SAIDA/$nome.log" 2>&1 &
  pid=$!

  tentativas=0
  until netstat -an 2>/dev/null | grep -q "11008.*LISTENING" || [ $tentativas -ge 60 ]; do
    sleep 1
    tentativas=$((tentativas + 1))
  done

  "$GODOT" --headless --path "$PROJ" --modo=training \
      --fixed-fps 2000 --disable-render-loop --cone=$CONE \
      --voltas="$SAIDA/${nome}_voltas.csv" >/dev/null 2>&1

  wait $pid
  echo "  concluido $(date +%H:%M:%S)"
  echo
done

echo "TODAS AS EXECUCOES CONCLUIDAS"
