extends Node3D
const Pistas := preload("res://scenes/track/pistas.gd")
## Registra, quadro a quadro, o quanto o piloto heuristico se afasta da
## trajetoria que deveria seguir - em posicao e em velocidade.
##
##   Godot.exe --headless --path <proj> res://tests/diag_heuristica.tscn \
##             --linha=<arquivo.csv> [--pista=<nome>] [--duracao=60]

var carro: Car
var piloto
var t := 0.0
var duracao := 60.0
var _lx := PackedFloat64Array()
var _lz := PackedFloat64Array()
var _lv := PackedFloat64Array()
var _ds := 1.0
var _erro_lat := PackedFloat64Array()
var _erro_vel := PackedFloat64Array()
var _acel := PackedFloat64Array()
var _freio := PackedFloat64Array()
var _volante := PackedFloat64Array()
var _lat_usada := PackedFloat64Array()
var _n := 0


func _ready():
	var linha := ""
	for a in OS.get_cmdline_args():
		if a.begins_with("--linha="):
			linha = a.split("=")[1]
		elif a.begins_with("--duracao="):
			duracao = float(a.split("=")[1])

	var gs: Node3D = load("res://scenes/game_scene/game_scene.tscn").instantiate()
	gs.get_node("Sync").control_mode = 0
	var cars = gs.get_node("Cars")
	cars.training_mode = true
	cars.number_of_cars_to_spawn = 1
	cars.ui = gs.get_node("UI")
	gs.get_node("Track").training_mode = true
	Pistas.aplicar(gs)
	add_child(gs)

	for c in cars.get_children():
		if c is Car:
			carro = c
			break
	carro.ai_controller.reset_after = 99999999

	piloto = load("res://scenes/car/piloto_heuristico.gd").new()
	piloto.carregar(linha)
	carro.piloto_heuristico = piloto

	# Copia da trajetoria, para medir o desvio por fora do piloto.
	var f := FileAccess.open(linha, FileAccess.READ)
	f.get_line()
	var s0 := 0.0
	while not f.eof_reached():
		var l := f.get_line().strip_edges()
		if l.is_empty():
			continue
		var c := l.split(",")
		if c.size() < 6:
			continue
		if _n == 0:
			s0 = float(c[0])
		elif _n == 1:
			_ds = float(c[0]) - s0
		_lx.append(float(c[1]))
		_lz.append(float(c[2]))
		_lv.append(float(c[5]))
		_n += 1
	f.close()


func _physics_process(delta):
	if carro == null or _n == 0:
		return
	t += delta

	var i := int(round(carro.current_offset / _ds)) % _n
	var alvo := Vector2(_lx[i], _lz[i])
	var aqui := Vector2(carro.global_position.x, carro.global_position.z)
	_erro_lat.append(aqui.distance_to(alvo))

	var v: float = (carro.global_transform.basis.inverse() * carro.linear_velocity).z
	_erro_vel.append(v - _lv[i])

	_acel.append(carro.requested_throttle)
	_freio.append(carro.requested_brake)
	_volante.append(absf(carro.requested_steering))
	# Aceleracao lateral efetivamente usada, em fracao do orcamento do pneu.
	var guinada: float = carro.angular_velocity.y
	_lat_usada.append(absf(guinada * v) / (carro.grip_g * 9.81))

	if t < duracao:
		return

	print("DIAG acelerador cheio em %.0f%% do tempo | freio ativo em %.0f%% | volante no batente em %.0f%%" % [
		_fracao(_acel, 0.99) * 100.0, _fracao(_freio, 0.01) * 100.0, _fracao(_volante, 0.99) * 100.0])
	print("DIAG aderencia lateral usada: media %.0f%% do orcamento, p95 %.0f%%" % [
		_media(_lat_usada) * 100.0, _percentil(_lat_usada, 95) * 100.0])
	print("DIAG desvio_lateral medio=%.2f m  p95=%.2f m  max=%.2f m" % [
		_media(_erro_lat), _percentil(_erro_lat, 95), _maior(_erro_lat)])
	print("DIAG erro_velocidade medio=%.2f m/s  p5=%.2f  p95=%.2f  (negativo = lento)" % [
		_media(_erro_vel), _percentil(_erro_vel, 5), _percentil(_erro_vel, 95)])
	print("DIAG batidas=%d" % carro.toques_no_muro)
	get_tree().quit()


func _fracao(a: PackedFloat64Array, limiar: float) -> float:
	var c := 0
	for x in a:
		if x >= limiar:
			c += 1
	return float(c) / maxf(a.size(), 1)


func _media(a: PackedFloat64Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / maxf(a.size(), 1)


func _maior(a: PackedFloat64Array) -> float:
	var m := a[0]
	for x in a:
		m = maxf(m, x)
	return m


func _percentil(a: PackedFloat64Array, q: float) -> float:
	var copia := a.duplicate()
	copia.sort()
	return copia[clampi(int(q / 100.0 * copia.size()), 0, copia.size() - 1)]
