#!/usr/bin/env bash
# Mede cada politica treinada nos dois circuitos e imprime uma linha por
# medicao, em CSV. Cada condicao e avaliada com a informacao geometrica com
# que foi treinada: a linha central para o RL puro, a trajetoria calculada
# para o RL com heuristica.
set -u
export PYTHONIOENCODING=utf-8

GODOT="/c/Users/adm/Desktop/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe"
PY="/c/Users/adm/Desktop/godot-rl-ref/.venv/Scripts/python.exe"
PROJ="C:/tcc/projeto-tcc"
SAIDA="C:/tcc/treinos"
DUR=300
SEMENTES="${*:-0 1 2}"

cp "$PROJ/model.onnx" "$SAIDA/_bkp.onnx"
echo "condicao,semente,circuito,distancia_m,vel_media_kmh,vel_max_kmh,batidas,ritmo_s"

medir() {
  local cond="$1" semente="$2" nome="$3" obs="$4"
  if ! "$PY" "$PROJ/train/onnx_arquivo_unico.py"         "$SAIDA/$nome.onnx" "$PROJ/model.onnx" >/dev/null 2>&1; then
    echo "ERRO: falha ao converter $nome" >&2
    return 1
  fi
  # Sem isto, uma conversao silenciosamente falha faria medir o modelo anterior
  # e render seis resultados identicos sem que nada parecesse errado.
  local assinatura
  assinatura=$(md5sum "$PROJ/model.onnx" | cut -c1-8)
  echo "  [$nome -> model.onnx $assinatura]" >&2

  for circ in "treinamento::694.01" "interlagos:--pista=interlagos_reduzido:1075.94"; do
    IFS=: read -r rotulo pista L <<< "$circ"
    local flag_obs=""
    if [ -n "$obs" ]; then
      if [ "$rotulo" = "treinamento" ]; then
        flag_obs="--linha_obs=$SAIDA/linha_pista1.csv"
      else
        flag_obs="--linha_obs=$SAIDA/linha_ilg_red.csv"
      fi
    fi
    set -- $("$GODOT" --headless --path "$PROJ" res://tests/medir_politica.tscn \
        --fixed-fps 2000 --disable-render-loop --duracao=$DUR \
        $pista $flag_obs 2>&1 | grep RESULTADO)
    local ritmo
    ritmo=$("$PY" -c "print('%.2f' % ($DUR/($2/$L)))")
    echo "$cond,$semente,$rotulo,$2,$3,$4,$5,$ritmo"
  done
}

for s in $SEMENTES; do medir "rl_puro"      "$s" "rl_s$s"  ""; done
for s in $SEMENTES; do medir "rl_heuristica" "$s" "rlh_s$s" "sim"; done

cp "$SAIDA/_bkp.onnx" "$PROJ/model.onnx"
rm -f "$SAIDA/_bkp.onnx"
