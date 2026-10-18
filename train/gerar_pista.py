# -*- coding: utf-8 -*-
"""Gera um tracado para o simulador a partir de dados do OpenStreetMap.

O OSM entrega um circuito partido em dezenas de trechos, fora de ordem e
misturado com pit lane, vias de servico e variantes do traçado. Este
utilitario costura a volta principal, projeta para metros, escala e grava um
recurso Curve3D que o ambiente carrega com --pista=<nome>.

    python train/gerar_pista.py <entrada.geojson> <nome> [--escala=K]

A costura e verificada pelo fechamento da volta e pela extensao resultante,
que deve bater com a extensao oficial do circuito.
"""
import json
import math
import os
import sys

R_TERRA = 6378137.0
## Vias que não fazem parte da volta. O OSM etiqueta tudo como "raceway".
EXCLUIR = ("pit lane", "quartermile")
## Extremos de trechos vizinhos compartilham o mesmo no no OSM, entao a
## tolerancia so precisa cobrir ruido de arredondamento.
TOLERANCIA_M = 0.5


def projetar(features):
    """Equirretangular em torno do centroide. A 1 km de extensao, o erro de
    projecao e milimetrico - irrelevante perto da largura da pista."""
    pts = [c for f in features for c in f["geometry"]["coordinates"]]
    lon0 = sum(p[0] for p in pts) / len(pts)
    lat0 = sum(p[1] for p in pts) / len(pts)
    k = math.cos(math.radians(lat0))

    def p(c):
        return (
            (c[0] - lon0) * k * math.radians(1.0) * R_TERRA,
            (c[1] - lat0) * math.radians(1.0) * R_TERRA,
        )

    return p


def carregar(caminho):
    """Aceita tanto GeoJSON (overpass-turbo) quanto o JSON cru do Overpass."""
    d = json.load(open(caminho, encoding="utf-8"))
    if "features" in d:
        feats = [f for f in d["features"]
                 if f.get("geometry", {}).get("type") == "LineString"]
    else:
        feats = [{"properties": e.get("tags", {}),
                  "geometry": {"type": "LineString",
                               "coordinates": [[g["lon"], g["lat"]]
                                               for g in e["geometry"]]}}
                 for e in d["elements"] if e.get("type") == "way" and "geometry" in e]

    proj = projetar(feats)
    vias = []
    for f in feats:
        nome = f["properties"].get("name") or f["properties"].get("@id", "?")
        if any(x in nome.lower() for x in EXCLUIR):
            continue
        xy = [proj(c) for c in f["geometry"]["coordinates"]]
        if len(xy) >= 2:
            vias.append({"nome": nome, "xy": xy})
    return vias


def comprimento(xy):
    return sum(math.dist(xy[i], xy[i + 1]) for i in range(len(xy) - 1))


def direcao(a, b):
    d = (b[0] - a[0], b[1] - a[1])
    n = math.hypot(*d) or 1.0
    return (d[0] / n, d[1] / n)


def costurar(vias, semente=0, com_marcas=False):
    """Caminha de trecho em trecho pelos extremos coincidentes. Em bifurcacao,
    segue o trecho que melhor preserva a direcao - num circuito, a continuacao
    da volta e sempre a mais reta; o que sai de lado e acesso ou variante."""
    usados = {semente}
    volta = list(vias[semente]["xy"])
    trechos = [vias[semente]["nome"]]
    marcas = [(0, vias[semente]["nome"])]

    while True:
        fim = volta[-1]
        entrada = direcao(volta[-2], volta[-1])
        melhor, melhor_xy, melhor_cos = None, None, -2.0

        for i, v in enumerate(vias):
            if i in usados:
                continue
            for xy in (v["xy"], v["xy"][::-1]):
                if math.dist(xy[0], fim) > TOLERANCIA_M:
                    continue
                c = sum(a * b for a, b in zip(entrada, direcao(xy[0], xy[1])))
                if c > melhor_cos:
                    melhor, melhor_xy, melhor_cos = i, xy, c

        if melhor is None:
            break
        usados.add(melhor)
        marcas.append((len(volta), vias[melhor]["nome"]))
        volta.extend(melhor_xy[1:])
        trechos.append(vias[melhor]["nome"])
        if math.dist(volta[-1], volta[0]) <= TOLERANCIA_M:
            break

    if com_marcas:
        return volta, trechos, marcas
    return volta, trechos


def reamostrar(volta, passo):
    """Reamostra a passo constante, para os pontos de controle ficarem
    distribuidos pela extensao e nao pela densidade do levantamento."""
    saida, acc, i = [volta[0]], 0.0, 0
    while i < len(volta) - 1:
        d = math.dist(volta[i], volta[i + 1])
        if acc + d < passo:
            acc += d
            i += 1
            continue
        t = (passo - acc) / d
        novo = (volta[i][0] + t * (volta[i + 1][0] - volta[i][0]),
                volta[i][1] + t * (volta[i + 1][1] - volta[i][1]))
        saida.append(novo)
        volta = volta[:i + 1] + [novo] + volta[i + 1:]
        i += 1
        acc = 0.0
    return saida


def raios(pontos, janela):
    """Raio do circulo por tres pontos (curvatura de Menger)."""
    n = len(pontos)
    out = []
    for i in range(n):
        a, b, c = pontos[(i - janela) % n], pontos[i], pontos[(i + janela) % n]
        ab, bc, ca = math.dist(a, b), math.dist(b, c), math.dist(c, a)
        area = abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) / 2
        out.append(1e9 if area < 1e-9 else ab * bc * ca / (4 * area))
    return sorted(out)


def escrever_tres(pontos, caminho):
    """Curve3D em formato texto. Os controles in/out recebem um terco da corda
    aos vizinhos, o que converte a poligonal numa Bezier suave que passa pelos
    pontos (equivalente a Catmull-Rom)."""
    n = len(pontos)
    dados = []
    for i, p in enumerate(pontos):
        ant, prox = pontos[(i - 1) % n], pontos[(i + 1) % n]
        tx, ty = (prox[0] - ant[0]) / 6.0, (prox[1] - ant[1]) / 6.0
        # O norte vai para -Z, e nao para +Z. Visto de cima no Godot (camera
        # olhando para -Y), +Z aponta para a parte de baixo da tela, ou seja,
        # para o sul. Mapear norte em +Z espelharia o circuito e inverteria a
        # mao de todas as curvas - um circuito anti-horario viraria horario.
        dados += [-tx, 0.0, ty, tx, 0.0, -ty, p[0], 0.0, -p[1]]

    corpo = ", ".join("%.4f" % v for v in dados)
    with open(caminho, "w", encoding="utf-8", newline="\n") as f:
        f.write('[gd_resource type="Curve3D" format=3]\n\n')
        f.write("[resource]\n")
        f.write("bake_interval = 0.5\n")
        f.write("_data = {\n")
        f.write('"points": PackedVector3Array(%s),\n' % corpo)
        f.write('"tilts": PackedFloat32Array(%s)\n' % ", ".join(["0.0"] * n))
        f.write("}\n")
        f.write("point_count = %d\n" % n)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    entrada, nome = sys.argv[1], sys.argv[2]
    escala = 1.0
    largada = ""
    for a in sys.argv[3:]:
        if a.startswith("--escala="):
            escala = float(a.split("=")[1])
        elif a.startswith("--largada="):
            largada = a.split("=")[1]

    vias = carregar(entrada)
    print("trechos aproveitaveis: %d" % len(vias))

    # Semeia pelo trecho mais longo: ele certamente pertence a volta principal.
    semente = max(range(len(vias)), key=lambda i: comprimento(vias[i]["xy"]))
    volta, trechos, marcas = costurar(vias, semente, com_marcas=True)

    fechamento = math.dist(volta[-1], volta[0])
    real = comprimento(volta)
    print("semente        : %s" % vias[semente]["nome"])
    print("trechos unidos : %d" % len(trechos))
    print("fechamento     : %.2f m" % fechamento)
    print("extensao real  : %.1f m" % real)
    if fechamento > TOLERANCIA_M:
        raise SystemExit("ERRO: a volta nao fechou - a costura falhou.")

    volta = volta[:-1]

    # A costura comeca no trecho semente, que e so o mais longo - nada a ver
    # com a linha de largada real. Gira a sequencia para a volta comecar no
    # trecho pedido, porque o carro nasce no offset zero da curva.
    if largada:
        alvo = [i for i, n in marcas if largada.lower() in n.lower()]
        if not alvo:
            raise SystemExit("nao achei trecho '%s'. Disponiveis: %s" % (
                largada, ", ".join(sorted({n for _, n in marcas
                                           if not n.startswith("way/")}))))
        k = alvo[0] % len(volta)
        volta = volta[k:] + volta[:k]
        print("largada deslocada para o inicio de '%s' (ponto %d)" % (largada, k))

    escalado = [(x * escala, y * escala) for x, y in volta]
    print("\nescala %.3f -> extensao %.1f m" % (escala, real * escala))

    # Um ponto de controle a cada ~8 m da escala final: fino o bastante para as
    # curvas e grosso o bastante para nao transformar ruido em curvatura.
    pontos = reamostrar(escalado, 8.0)
    print("pontos de controle: %d" % len(pontos))

    rr = raios(pontos, 2)
    print("\nraios resultantes:")
    for p, rotulo in ((0, "minimo"), (5, "p5"), (50, "mediana"), (75, "p75")):
        print("  %-8s %8.1f m" % (rotulo, rr[min(int(p / 100 * len(rr)), len(rr) - 1)]))

    destino = os.path.join("pistas", nome + ".tres")
    escrever_tres(pontos, destino)
    print("\ngravado: %s" % destino)


if __name__ == "__main__":
    main()
