# -*- coding: utf-8 -*-
"""Junta um modelo ONNX e seus pesos externos num arquivo unico.

O exportador do PyTorch 2.x grava os pesos num arquivo separado (`.onnx.data`)
e guarda o NOME dele dentro do `.onnx`. Renomear ou mover o par quebra a
referencia, e o Godot falha ao carregar com "file_size: o sistema nao pode
encontrar o arquivo especificado".

Este utilitario reescreve o modelo com os pesos embutidos, produzindo um
arquivo unico que pode ser copiado para qualquer lugar.

    python train/onnx_arquivo_unico.py <entrada.onnx> <saida.onnx>
"""
import os
import sys

import onnx


def juntar(entrada: str, saida: str) -> None:
    if not os.path.isfile(entrada):
        raise SystemExit("arquivo nao encontrado: %s" % entrada)

    # load_external_data=True e o padrao: le o .onnx.data que estiver ao lado.
    modelo = onnx.load(entrada)
    onnx.checker.check_model(modelo)

    destino = os.path.abspath(saida)
    os.makedirs(os.path.dirname(destino) or ".", exist_ok=True)
    onnx.save_model(modelo, destino, save_as_external_data=False)

    entradas = [(e.name, [d.dim_value or d.dim_param for d in e.type.tensor_type.shape.dim])
                for e in modelo.graph.input]
    saidas = [s.name for s in modelo.graph.output]

    print("entrada: %s" % entrada)
    print("saida:   %s  (%.1f KB, arquivo unico)" % (destino, os.path.getsize(destino) / 1024))
    print("  entradas do grafo: %s" % ", ".join("%s %s" % (n, s) for n, s in entradas))
    print("  saidas do grafo:   %s" % ", ".join(saidas))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    juntar(sys.argv[1], sys.argv[2])
