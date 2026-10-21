#!/usr/bin/env bash
# Replicacao das condicoes de Aprendizado por Reforco.
#
# Treina 3 sementes para cada condicao, no mesmo estado do codigo, de modo que
# a comparacao entre elas seja atribuivel ao tratamento e nao a variacao entre
# execucoes. A heuristica pura nao aparece aqui: nao ha aprendizado nela.
#
# Ao contrario de treinar.bat, nao abre janela para o lado Python - os dois
# processos sao encadeados aqui mesmo.
set -u

# O exportador do PyTorch imprime simbolos fora do cp1252, e o cleanup do
# train_sb3.py exporta o ONNX ANTES de salvar o modelo: sem isto, a excecao de
# codificacao derruba os dois e o treino inteiro se perde.
export PYTHONIOENCODING=utf-8

GODOT="/c/Users/adm/Desktop/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe"
PY="/c/Users/adm/Desktop/godot-rl-ref/.venv/Scripts/python.exe"
PROJ="C:/tcc/projeto-tcc"
SAIDA="C:/tcc/treinos"
PASSOS=300000
TRAJ="C:/tcc/treinos/linha_pista1.csv"

# Sementes a executar. Sem argumentos, repete as tres originais; com eles,
# acrescenta as que faltarem - util para ampliar a replicacao sem refazer o
# que ja foi medido.
SEMENTES="${*:-0 1 2}"

treinar() {
  local nome="$1" semente="$2" obs="$3"
  echo "=============================================================="
  echo " $nome   (semente $semente)   $(date +%H:%M:%S)"
  echo "=============================================================="

  "$PY" "$PROJ/train/train_sb3.py" \
      --timesteps=$PASSOS --seed="$semente" --speedup=20 \
      --experiment_dir="$SAIDA" --experiment_name="$nome" \
      --save_model_path="$SAIDA/$nome" \
      --onnx_export_path="$SAIDA/$nome.onnx" >"$SAIDA/$nome.log" 2>&1 &
  local pid=$!

  # Espera o servidor abrir antes de subir o simulador.
  local tentativas=0
  until netstat -an 2>/dev/null | grep -q "11008.*LISTENING" || [ $tentativas -ge 60 ]; do
    sleep 1
    tentativas=$((tentativas + 1))
  done

  "$GODOT" --headless --path "$PROJ" --modo=training \
      --fixed-fps 2000 --disable-render-loop $obs \
      --voltas="$SAIDA/${nome}_voltas.csv" >/dev/null 2>&1

  wait $pid
  echo "  concluido $(date +%H:%M:%S)"
  echo
}

for s in $SEMENTES; do
  treinar "rl_s$s" "$s" ""
done

for s in $SEMENTES; do
  treinar "rlh_s$s" "$s" "--linha_obs=$TRAJ"
done

echo "TODAS AS EXECUCOES CONCLUIDAS"
