extends Node3D
const Pistas := preload("res://scenes/track/pistas.gd")
## Mede o desempenho da politica que estiver em model.onnx.
##
## Roda a inferencia por um tempo fixo e imprime distancia percorrida,
## velocidade media e batidas. Serve para comparar checkpoints objetivamente,
## em vez de julgar pela observacao visual.
##
##   Godot.exe --headless --path <projeto> res://tests/medir_politica.tscn \
##             --fixed-fps 2000 --disable-render-loop

var duracao := 30.0
## Um quadro de fisica a 120 km/h anda 0,55 m. Qualquer salto muito maior que
## isso e teletransporte do reset, nao deslocamento: nao entra na conta.
const SALTO_DE_RESET := 5.0

var carro: Car
var t := 0.0
var _progresso := 0.0
var _offset_anterior := 0.0
var _soma_v := 0.0
var _amostras := 0
var _v_max := 0.0
var _empurrao := 0.0


func _ready():
	var gs: Node3D = load("res://scenes/game_scene/game_scene.tscn").instantiate()
	var sync = gs.get_node("Sync")
	sync.control_mode = sync.ControlModes.ONNX_INFERENCE

	# Com --linha=<arquivo>, mede a heuristica em vez de uma politica treinada:
	# mesmo veiculo, mesma pista, mesma janela, so muda quem dirige.
	var linha := ""
	for a in OS.get_cmdline_args():
		if a.begins_with("--linha="):
			linha = a.split("=")[1]
	if not linha.is_empty():
		sync.control_mode = sync.ControlModes.HUMAN
	# Com --amostrar, sorteia a acao em vez de usar a media da distribuicao -
	# que e como o agente se comporta durante o treino.
	if "--amostrar" in OS.get_cmdline_args():
		sync.deterministic_inference = false

	# training_mode evita a contagem regressiva a cada reset, que agora pode
	# acontecer muitas vezes dentro da janela de medida.
	var cars = gs.get_node("Cars")
	cars.training_mode = true
	cars.number_of_cars_to_spawn = 1
	cars.ui = gs.get_node("UI")
	gs.get_node("Track").training_mode = true

	# --espelhar nega o X de todos os pontos de controle: mesma distribuicao de
	# raios, todas as curvas trocadas de lado. E um teste de generalizacao sem
	# nenhuma decisao de projeto nova - a dificuldade e identica por construcao.
	if "--espelhar" in OS.get_cmdline_args():
		var curva: Curve3D = gs.get_node("Track").track_path.curve
		for i in curva.point_count:
			var pos := curva.get_point_position(i)
			var ent := curva.get_point_in(i)
			var sai := curva.get_point_out(i)
			curva.set_point_position(i, Vector3(-pos.x, pos.y, pos.z))
			curva.set_point_in(i, Vector3(-ent.x, ent.y, ent.z))
			curva.set_point_out(i, Vector3(-sai.x, sai.y, sai.z))
		print("PISTA ESPELHADA")

	Pistas.aplicar(gs)
	add_child(gs)

	# Troca a referencia geometrica das observacoes pela trajetoria calculada.
	var obs := ""
	var desvio := ""
	for a in OS.get_cmdline_args():
		if a.begins_with("--linha_obs="):
			obs = a.split("=")[1]
		elif a.begins_with("--linha_desvio="):
			desvio = a.split("=")[1]
	var traj = null
	if not obs.is_empty():
		traj = load("res://scenes/car/trajetoria.gd").new()
		if not traj.carregar(obs):
			traj = null

	for c in cars.get_children():
		if c is Car:
			carro = c
			break
	if not linha.is_empty():
		var piloto = load("res://scenes/car/piloto_heuristico.gd").new()
		if piloto.carregar(linha):
			carro.piloto_heuristico = piloto

	if traj != null:
		carro.trajetoria_referencia = traj
	if not desvio.is_empty():
		var td = load("res://scenes/car/trajetoria.gd").new()
		if td.carregar(desvio):
			carro.trajetoria_desvio = td

	# A janela de medida aqui e o tempo, nao o episodio.
	carro.ai_controller.reset_after = 99999999
	_offset_anterior = carro.current_offset

	# --empurrao=<m/s> da uma largada lancada, para separar "nao sabe dirigir"
	# de "nao sabe sair do lugar".
	for a in OS.get_cmdline_args():
		if a.begins_with("--empurrao="):
			_empurrao = float(a.split("=")[1])
		elif a.begins_with("--duracao="):
			duracao = float(a.split("=")[1])


func _physics_process(delta):
	if carro == null:
		return

	# Depois do primeiro meio segundo: antes disso o _just_reset do carro zera
	# a velocidade no mesmo quadro e o empurrao se perde.
	if _empurrao > 0.0 and t > 0.5:
		carro.linear_velocity = carro.global_transform.basis.z * _empurrao
		_empurrao = 0.0

	t += delta

	var avanco := carro.current_offset - _offset_anterior
	var L := carro.track_length
	if avanco > L / 2.0:
		avanco -= L
	elif avanco < -L / 2.0:
		avanco += L
	if absf(avanco) < SALTO_DE_RESET:
		_progresso += avanco
	_offset_anterior = carro.current_offset

	var v: float = (carro.global_transform.basis.inverse() * carro.linear_velocity).z
	_soma_v += absf(v)
	_amostras += 1
	_v_max = maxf(_v_max, v)

	if t < duracao:
		return

	var v_media: float = (_soma_v / maxf(_amostras, 1)) * 3.6
	print("RESULTADO %.1f %.1f %.1f %d %.1f" % [
		_progresso, v_media, _v_max * 3.6, carro.toques_no_muro,
		_progresso / L * 100.0])
	get_tree().quit()
