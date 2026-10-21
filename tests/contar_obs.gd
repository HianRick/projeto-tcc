extends Node3D
const Pistas := preload("res://scenes/track/pistas.gd")
## Conta e imprime o vetor de observacoes entregue ao agente.

func _ready():
	var gs: Node3D = load("res://scenes/game_scene/game_scene.tscn").instantiate()
	gs.get_node("Sync").control_mode = 0
	var cars = gs.get_node("Cars")
	cars.training_mode = true
	cars.number_of_cars_to_spawn = 1
	cars.ui = gs.get_node("UI")
	gs.get_node("Track").training_mode = true
	Pistas.aplicar(gs)
	add_child(gs)

	var carro: Car = null
	for c in cars.get_children():
		if c is Car:
			carro = c
			break

	for a in OS.get_cmdline_args():
		if a.begins_with("--linha_desvio="):
			var t = load("res://scenes/car/trajetoria.gd").new()
			if t.carregar(a.split("=")[1]):
				carro.trajetoria_desvio = t

	var obs: Array = carro.ai_controller.get_obs_for_car(carro)
	print("OBS total=%d" % obs.size())
	if carro.trajetoria_desvio != null:
		var d: Array = carro.get_desvios_da_trajetoria(3, 20)
		print("OBS desvios=%s  (em metros: %.2f %.2f %.2f)" % [
			str(d).pad_decimals(3), d[0] * 4.5, d[1] * 4.5, d[2] * 4.5])
	get_tree().quit()
