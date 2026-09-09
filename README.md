# ProjetoTcc — Ambiente de simulação Godot + RL

Ambiente tridimensional de corrida construído para o trabalho de conclusão
**"Geração de linha ideal em simulação de pistas de corrida através de ML"**,
que compara um modelo heurístico e um agente de aprendizado por reforço na
descoberta da trajetória de menor tempo.

O ambiente parte do exemplo *Hovercraft Racing* do
[godot_rl_agents_examples](https://github.com/edbeeching/godot_rl_agents_examples)
e foi reescrito: o veículo deixou de ser um aerobarco e passou a ter física de
automóvel em grandezas reais, com aderência lateral, círculo de tração e
direção sensível à velocidade.

## Requisitos

| Componente | Versão | Observação |
|---|---|---|
| Godot Engine | 4.7.1 **mono** | a variante mono é obrigatória: a inferência ONNX usa C# |
| .NET SDK | 8.0 | o SDK 7 não compila — `Godot.NET.Sdk` 4.7 exige `net8.0` |
| Python | 3.12 | apenas para o treino |

Pacotes Python:

```
pip install "godot-rl[sb3]" onnxscript
```

## Como rodar

O modo é escolhido na linha de comando, então o mesmo projeto (ou binário
exportado) serve para os três usos.

**Dirigir** — `W` acelera, `S` freia, `A`/`D` esterçam:

```
Godot_v4.7.1-stable_mono_win64.exe --path . --modo=test_drive
```

**Verificar a física** — sonda automatizada, imprime as medidas em segundos:

```
Godot_v4.7.1-stable_mono_win64.exe --headless --path . \
  res://tests/car_probe.tscn --fixed-fps 500 --disable-render-loop
```

**Treinar** — dois processos. O Python é servidor e **sobe primeiro**:

```
python train/train_sb3.py --timesteps=1000000 --speedup=20 \
  --experiment_dir=<pasta> --experiment_name=<nome> --seed=0 \
  --onnx_export_path=<pasta>/<nome>.onnx
```

```
Godot_v4.7.1-stable_mono_win64.exe --headless --path . --modo=training \
  --fixed-fps 2000 --disable-render-loop --voltas=<pasta>/voltas.csv
```

**Assistir ao agente treinado:**

```
python train/onnx_arquivo_unico.py <treino>.onnx model.onnx
Godot_v4.7.1-stable_mono_win64.exe --path . --modo=inference
```

O passo de conversão é obrigatório: o exportador do PyTorch 2.x grava os pesos
num arquivo separado e guarda o nome dele dentro do `.onnx`, o que quebra ao
mover o par. O utilitário reescreve tudo num arquivo só.

## Interface de aprendizado

**27 observações:** velocidade longitudinal e lateral, taxa de guinada, ângulo
atual das rodas, três pontos da pista à frente (60 m) e 17 raios de um sensor
em leque de 360°.

**3 ações contínuas:** `throttle`, `brake` e `steering`. Acelerador e freio são
independentes, o que permite *trail braking*.

**Episódio:** 3000 passos de física (50 s), definido em `reset_after` no
`CarAIController`. Vale apenas para o agente — quem dirige nunca é
reposicionado.

## O veículo

Física em grandezas reais, toda exposta no inspetor e **verificada por medição**
(`tests/car_probe.tscn`):

| parâmetro | valor |
|---|---|
| massa | 300 kg |
| velocidade de pico | 120 km/h |
| aceleração | 8,0 m/s² |
| frenagem | 14,0 m/s² |
| aderência | 1,50 g |
| esterço máximo | 30° |
| entre-eixos | 1,20 m |

A aderência é um **orçamento único** dividido entre longitudinal e lateral pelo
círculo de tração — gastar aderência freando tira aderência para curvar. É esse
acoplamento que faz existir uma trajetória de menor tempo distinta do caminho
geometricamente mais curto.

A direção é sensível à velocidade: o curso útil do volante é limitado ao que a
aderência comporta, para o comando permanecer proporcional em qualquer
velocidade.

## Cronometragem

Instrumentação passiva (`scenes/car/cronometro.gd`): registra tempo de volta,
velocidade média e contatos com muro, sem encerrar episódio nem interferir na
simulação. Conta em tempo de **simulação**, então `--speedup` não altera os
tempos medidos.

Passando `--voltas=<caminho.csv>` grava um CSV; sem isso, imprime no console.

## Estrutura

```
addons/godot_rl_agents/   plugin de RL: sync, controladores, sensores, ONNX
addons/godot_mcp/         plugin de editor (ferramenta de desenvolvimento)
scenes/car/               veículo, controlador de IA, cronômetro
scenes/track/             pista procedural e cenário
scenes/models/            modelos do veículo (Kenney Racing Kit, CC0)
tests/                    sondas de verificação da física e da cronometragem
train/                    treino e utilitários Python
```

## Licenças de terceiros

Modelos do veículo: [Kenney Racing Kit](https://kenney.nl/assets/racing-kit),
CC0. Licença em `scenes/models/`. Demais recursos herdados do repositório de
exemplos, em `asset-license.md`.
