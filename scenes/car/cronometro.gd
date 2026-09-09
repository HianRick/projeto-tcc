extends Node
class_name Cronometro
## Instrumentacao passiva: cronometra voltas sem interferir na simulacao.
##
## Nao encerra episodio, nao reposiciona o carro, nao decide vencedor. So
## observa o progresso ao longo da curva da pista e registra o tempo quando a
## distancia acumulada completa uma extensao inteira.
##
## Conta o tempo em segundos de SIMULACAO, e nao de relogio: com --speedup=20 o
## tempo de volta continua sendo o mesmo, que e o que interessa comparar.
##
## Para gravar as voltas em CSV, passe na linha de comando:
##   --voltas=C:\caminho\voltas.csv

const CABECALHO := "carro,volta,tempo_s,velocidade_media_kmh,toques_muro"

var _carro: Car
var _caminho_csv := ""

## Distancia percorrida ao longo da pista desde o inicio, sem dar a volta no
## contador. E o que permite detectar uma volta mesmo se o carro vacilar para
## tras no meio dela.
var _progresso := 0.0
var _progresso_da_ultima_volta := 0.0
var _offset_anterior := 0.0
var _tempo_da_volta := 0.0
var _toques_no_inicio_da_volta := 0

var voltas_completas := 0
var melhor_tempo := INF
var ultimo_tempo := 0.0


func _ready():
	_carro = get_parent() as Car
	assert(_carro != null, "o Cronometro precisa ser filho de um Car")
	for argumento in OS.get_cmdline_args():
		if argumento.begins_with("--voltas="):
			_caminho_csv = argumento.split("=", true, 1)[1]
	set_physics_process(false)


## Chamado pelo carro depois que ele ja esta posicionado e com a pista definida.
func iniciar():
	_offset_anterior = _carro.current_offset
	_progresso = 0.0
	_progresso_da_ultima_volta = 0.0
	_tempo_da_volta = 0.0
	_toques_no_inicio_da_volta = _carro.toques_no_muro
	set_physics_process(true)


## O carro foi reposicionado: a volta em andamento perde o sentido, entao ela e
## descartada. As voltas ja completadas continuam valendo.
func reiniciar_volta():
	_offset_anterior = _carro.current_offset
	_progresso_da_ultima_volta = _progresso
	_tempo_da_volta = 0.0
	_toques_no_inicio_da_volta = _carro.toques_no_muro


func _physics_process(delta):
	_tempo_da_volta += delta

	var offset: float = _carro.current_offset
	var comprimento: float = _carro.track_length
	var avanco := offset - _offset_anterior

	# Corrige o momento em que o contador da a volta, nos dois sentidos.
	if avanco > comprimento / 2.0:
		avanco -= comprimento
	elif avanco < -comprimento / 2.0:
		avanco += comprimento

	_progresso += avanco
	_offset_anterior = offset

	if _progresso - _progresso_da_ultima_volta < comprimento:
		return

	# Volta completa.
	voltas_completas += 1
	ultimo_tempo = _tempo_da_volta
	var media_kmh := (comprimento / _tempo_da_volta) * 3.6
	var toques: int = _carro.toques_no_muro - _toques_no_inicio_da_volta
	var recorde := _tempo_da_volta < melhor_tempo
	if recorde:
		melhor_tempo = _tempo_da_volta

	print("[volta] %s  n=%d  tempo=%.2fs  media=%.1f km/h  toques=%d%s" % [
		_carro.name, voltas_completas, _tempo_da_volta, media_kmh, toques,
		"  <- melhor" if recorde else ""])

	if not _caminho_csv.is_empty():
		_gravar_csv("%s,%d,%.3f,%.2f,%d" % [
			_carro.name, voltas_completas, _tempo_da_volta, media_kmh, toques])

	_progresso_da_ultima_volta += comprimento
	_tempo_da_volta = 0.0
	_toques_no_inicio_da_volta = _carro.toques_no_muro


## Abre em modo de acrescimo a cada volta, para varios carros poderem escrever
## no mesmo arquivo durante o treino.
func _gravar_csv(linha: String):
	if not FileAccess.file_exists(_caminho_csv):
		var novo := FileAccess.open(_caminho_csv, FileAccess.WRITE)
		if novo == null:
			push_warning("nao consegui criar %s" % _caminho_csv)
			_caminho_csv = ""
			return
		novo.store_line(CABECALHO)
		novo.close()

	var arquivo := FileAccess.open(_caminho_csv, FileAccess.READ_WRITE)
	if arquivo == null:
		return
	arquivo.seek_end()
	arquivo.store_line(linha)
	arquivo.close()
