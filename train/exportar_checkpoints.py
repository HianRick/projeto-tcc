# -*- coding: utf-8 -*-
"""Converte os checkpoints de um treino em modelos ONNX de arquivo unico.

Durante o treino, o Stable-Baselines3 salva a politica a cada N passos em
arquivos `.zip`. Esses arquivos nao rodam dentro do Godot: e preciso export\u00e1-los
para ONNX e, em seguida, embutir os pesos num arquivo unico (o exportador do
PyTorch 2.x grava os pesos separados e registra o nome do arquivo dentro do
modelo, o que quebra ao mover o par).

Este utilitario faz as duas etapas para todos os checkpoints de uma execucao,
nomeando a saida pelo numero de passos, de modo que assistir aos modelos em
ordem mostra a evolucao do aprendizado.

    python train/exportar_checkpoints.py <pasta-de-treinos> <nome-da-execucao>

Exemplo:
    python train/exportar_checkpoints.py C:\\tcc\\treinos m2_seed0
"""
import os
import re
import sys

import onnx
from stable_baselines3 import PPO
from godot_rl.wrappers.onnx.stable_baselines_export import export_model_as_onnx


def passos_do_nome(caminho: str) -> int:
    """O callback do SB3 nomeia os arquivos como <prefixo>_<passos>_steps.zip."""
    m = re.search(r"_(\d+)_steps\.zip$", os.path.basename(caminho))
    return int(m.group(1)) if m else -1


def converter(pasta_treinos: str, execucao: str) -> None:
    origem = os.path.join(pasta_treinos, execucao + "_checkpoints")
    if not os.path.isdir(origem):
        raise SystemExit(
            "nao encontrei %s\n"
            "o treino precisa ter sido rodado com --save_checkpoint_frequency" % origem
        )

    destino = os.path.join(pasta_treinos, execucao + "_evolucao")
    os.makedirs(destino, exist_ok=True)

    arquivos = sorted(
        (f for f in os.listdir(origem) if f.endswith(".zip")),
        key=passos_do_nome,
    )
    if not arquivos:
        raise SystemExit("nenhum checkpoint .zip em %s" % origem)

    print("convertendo %d checkpoints de '%s'" % (len(arquivos), execucao))
    print()

    temporario = os.path.join(destino, "_tmp.onnx")
    for nome in arquivos:
        passos = passos_do_nome(nome)
        saida = os.path.join(destino, "%s_%08d.onnx" % (execucao, passos))

        modelo = PPO.load(os.path.join(origem, nome), device="cpu")
        export_model_as_onnx(modelo, temporario)

        # Embute os pesos, para o arquivo poder ser copiado para o projeto.
        onnx.save_model(onnx.load(temporario), saida, save_as_external_data=False)
        print("  %9d passos  ->  %s  (%.1f KB)" % (
            passos, os.path.basename(saida), os.path.getsize(saida) / 1024))

    for resto in (temporario, temporario + ".data"):
        if os.path.exists(resto):
            os.remove(resto)

    print()
    print("pronto: %s" % destino)
    print("assista em ordem com  assistir_evolucao.bat %s" % execucao)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    converter(sys.argv[1], sys.argv[2])
