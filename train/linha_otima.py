# -*- coding: utf-8 -*-
"""Calcula a trajetoria de menor tempo dentro do corredor da pista.

Esta e a heuristica do trabalho: dado o tracado e os limites do veiculo,
determina por onde passar. Nao ha aprendizado - e calculo.

O metodo tem duas etapas, conforme a abordagem usual em planejamento de
trajetoria de corrida (HEILMEIER et al., 2019):

  1. Caminho de curvatura minima. Cada ponto da linha central recebe um
     deslocamento lateral livre dentro do corredor, e minimiza-se a soma dos
     quadrados da curvatura. Abrir a curva aumenta o raio, e raio maior
     sustenta mais velocidade.

  2. Perfil de velocidade sobre o caminho resultante, pelo mesmo calculo
     quase-estatico usado para o limite da linha central: teto de curva,
     passagem de avanco, passagem de recuo, acoplados pelo circulo de tracao.

Curvatura minima nao e exatamente tempo minimo - o otimo verdadeiro troca um
pouco de curvatura por zonas melhores de aceleracao -, mas fica muito mais
perto do otimo do que a linha central, que e a referencia que interessa.

    python train/linha_otima.py <tracado.txt> [--saida=linha.csv]
"""
import math
import sys

import numpy as np

# ---- veiculo (espelha scenes/car/car.gd) ---------------------------------
V_TOPO = 120.0 / 3.6
A_ACEL = 8.0
A_FREIO = 14.0
MU_G = 1.5 * 9.81
K_ARRASTO = A_ACEL / V_TOPO ** 2
LARGURA_CARRO = 1.09

# ---- pista ---------------------------------------------------------------
## Face interna dos muros, medida da linha central.
MEIA_PISTA = 4.5
## Folga entre a lateral do carro e o muro.
MARGEM = 0.10

PASSO = 1.0  # discretizacao do caminho, em metros


def carregar(caminho):
    pontos, L = [], None
    for linha in open(caminho):
        c = linha.split()
        if c[0] == "TRACKLEN":
            L = float(c[1])
        elif c[0] == "P":
            pontos.append((float(c[2]), float(c[3])))
    return np.array(pontos), L


def reamostrar(P, passo):
    """Reamostra o poligono fechado a passo constante."""
    d = np.linalg.norm(np.roll(P, -1, 0) - P, axis=1)
    s = np.concatenate([[0.0], np.cumsum(d)])
    total = s[-1]
    # O laco e fechado: o espacamento tem de dividir a extensao exatamente,
    # senao o segmento de fechamento fica mais curto que os demais e vira uma
    # quina artificial na emenda - que a curvatura discreta le como raio
    # minusculo.
    n_pontos = max(3, int(round(total / passo)))
    alvo = np.linspace(0.0, total, n_pontos, endpoint=False)
    x = np.interp(alvo, s[:-1], P[:, 0], period=total)
    y = np.interp(alvo, s[:-1], P[:, 1], period=total)
    return np.column_stack([x, y]), total


def normais(C):
    """Normal unitaria a esquerda da direcao de percurso, em cada ponto."""
    t = np.roll(C, -1, 0) - np.roll(C, 1, 0)
    t /= np.linalg.norm(t, axis=1, keepdims=True)
    return np.column_stack([-t[:, 1], t[:, 0]])


def _segunda_diferenca(X):
    return np.roll(X, 1, 0) - 2.0 * X + np.roll(X, -1, 0)


def curvatura_minima(C, n, a_max, iteracoes=60000):
    """Minimiza a soma dos quadrados da curvatura, com o deslocamento lateral
    preso ao corredor.

    A curvatura discreta e a segunda diferenca das posicoes. Como o ponto do
    caminho e C + alfa*n, o residuo e linear em alfa, e o problema vira
    minimos quadrados com restricao de caixa. Resolve-se por gradiente
    projetado com aceleracao de Nesterov: a matriz e pentadiagonal e enorme,
    mas o gradiente sai de duas operacoes vetoriais.
    """
    base = _segunda_diferenca(C)
    alfa = np.zeros(len(C))
    y = alfa.copy()
    t_ant = 1.0
    # A segunda diferenca tem norma espectral 4; o gradiente do quadrado, 32.
    passo = 1.0 / 32.0

    for _ in range(iteracoes):
        residuo = base + _segunda_diferenca(y[:, None] * n)
        grad = 2.0 * np.sum(_segunda_diferenca(residuo) * n, axis=1)
        novo = np.clip(y - passo * grad, -a_max, a_max)
        t_novo = (1.0 + math.sqrt(1.0 + 4.0 * t_ant ** 2)) / 2.0
        y = novo + ((t_ant - 1.0) / t_novo) * (novo - alfa)
        alfa, t_ant = novo, t_novo

    return alfa


def perfil_velocidade(P, aderencia=1.0):
    """Perfil quase-estatico sobre um caminho fechado qualquer.

    `aderencia` e a fracao do orcamento do pneu que o perfil se permite usar.
    Com 1.0 obtem-se o limite fisico, que serve de referencia mas nao e
    seguivel: qualquer desvio de trajetoria exige aderencia lateral alem da
    prevista, e o veiculo sai de frente. Um perfil de referencia para o
    controlador precisa reservar margem.
    """
    mu_g = MU_G * aderencia
    N = len(P)
    passos = np.linalg.norm(np.roll(P, -1, 0) - P, axis=1)

    a, b, c = np.roll(P, 1, 0), P, np.roll(P, -1, 0)
    ab = np.linalg.norm(b - a, axis=1)
    bc = np.linalg.norm(c - b, axis=1)
    ca = np.linalg.norm(a - c, axis=1)
    area = np.abs(
        (b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1])
        - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0])
    ) / 2.0
    R = np.where(area < 1e-9, 1e9, ab * bc * ca / (4.0 * np.maximum(area, 1e-9)))

    kappa = 1.0 / R
    v = np.minimum(V_TOPO, np.sqrt(mu_g * R))

    for _ in range(4):
        for i in range(N):              # avanco: limitado pela aceleracao
            j = (i + 1) % N
            lat = v[i] ** 2 * kappa[i]
            livre = min(A_ACEL, math.sqrt(max(0.0, mu_g ** 2 - lat ** 2)))
            livre -= K_ARRASTO * v[i] ** 2
            v[j] = min(v[j], math.sqrt(max(0.0, v[i] ** 2 + 2.0 * livre * passos[i])))
        for i in range(N - 1, -1, -1):  # recuo: limitado pela frenagem
            j = (i + 1) % N
            lat = v[j] ** 2 * kappa[j]
            livre = min(A_FREIO, math.sqrt(max(0.0, mu_g ** 2 - lat ** 2)))
            livre += K_ARRASTO * v[j] ** 2
            v[i] = min(v[i], math.sqrt(max(0.0, v[j] ** 2 + 2.0 * livre * passos[i])))

    return v, R, float(np.sum(passos / v)), float(np.sum(passos))


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    entrada = sys.argv[1]
    saida = ""
    ## Fracao do orcamento de aderencia que o perfil gravado se permite usar.
    aderencia = 1.0
    ## Folga entre a lateral do carro e o muro. Margem apertada rende volta
    ## mais rapida no papel, mas nao sobra espaco para erro de seguimento.
    margem = MARGEM
    for a in sys.argv[2:]:
        if a.startswith("--saida="):
            saida = a.split("=")[1]
        elif a.startswith("--aderencia="):
            aderencia = float(a.split("=")[1])
        elif a.startswith("--margem="):
            margem = float(a.split("=")[1])

    bruto, L = carregar(entrada)
    C, extensao = reamostrar(bruto, PASSO)
    n = normais(C)
    a_max = MEIA_PISTA - LARGURA_CARRO / 2.0 - margem

    print("tracado      : %s" % entrada)
    print("extensao     : %.2f m  (%d pontos a %.1f m)" % (extensao, len(C), PASSO))
    print("faixa lateral: +-%.2f m" % a_max)
    print()

    _, _, t_centro, _ = perfil_velocidade(C)

    alfa = curvatura_minima(C, n, a_max)
    P = C + alfa[:, None] * n
    v, R, t_linha, comprimento = perfil_velocidade(P)
    v_seguir, _, t_seguir, _ = perfil_velocidade(P, aderencia)

    print("                    tempo     extensao   vel. media   raio p5   raio p50")
    print("linha central   %8.2f s %9.1f m %9.1f km/h" % (
        t_centro, extensao, extensao / t_centro * 3.6))
    print("linha otima     %8.2f s %9.1f m %9.1f km/h %9.1f %10.1f" % (
        t_linha, comprimento, comprimento / t_linha * 3.6,
        np.percentile(R, 5), np.percentile(R, 50)))
    print()
    print("ganho sobre a linha central: %.2f s  (%.1f%%)" % (
        t_centro - t_linha, (1.0 - t_linha / t_centro) * 100.0))
    print("uso do corredor: |alfa| medio %.2f m, maximo %.2f m, no limite em %.0f%% do tracado" % (
        np.abs(alfa).mean(), np.abs(alfa).max(),
        (np.abs(alfa) > a_max - 0.01).mean() * 100.0))

    if aderencia < 1.0:
        print("perfil gravado com %.0f%% da aderencia: %.2f s" % (aderencia * 100, t_seguir))

    if saida:
        with open(saida, "w", newline="\n") as f:
            # s_centro e a posicao na LINHA CENTRAL correspondente a este
            # ponto. O carro ja conhece a propria projecao na linha central
            # (current_offset), entao esse campo permite localiza-lo na
            # trajetoria por indexacao direta, sem busca.
            f.write("s_centro,x,z,alfa,raio,velocidade_ms\n")
            ds_centro = extensao / len(P)
            for i in range(len(P)):
                f.write("%.4f,%.4f,%.4f,%.4f,%.2f,%.4f\n" % (
                    i * ds_centro, P[i, 0], P[i, 1], alfa[i],
                    min(R[i], 1e6), v_seguir[i]))
        print("\ngravado: %s" % saida)


if __name__ == "__main__":
    main()
