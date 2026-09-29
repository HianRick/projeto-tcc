extends Node3D
## Inspeciona o sensor de parede: angulos, alcance e leitura real na pista.

var carro: Car
var pronto := false


func _ready():
	var gs: Node3D = load("res://scenes/game_scene/game_scene.tscn").instantiate()
	gs.get_node("Sync").control_mode = 0  # HUMAN: sem rede, sem servidor
	var cars = gs.get_node("Cars")
	cars.training_mode = true
	cars.number_of_cars_to_spawn = 1
	cars.ui = gs.get_node("UI")
	gs.get_node("Track").training_mode = true
	add_child(gs)
	for c in cars.get_children():
		if c is Car:
			carro = c
			break


func _physics_process(_d):
	if carro == null or pronto:
		return
	pronto = true

	var s = carro.raycast_sensor_wall
	var leituras: Array = s.get_observation()
	var n := leituras.size()
	var passo: float = s.cone_width / n

	print("SENSOR n_raios=%d alcance=%.0fm cone=%.0f graus passo=%.1f graus" % [
		n, s.ray_length, s.cone_width, passo])
	print("idx  angulo   leitura   distancia")
	for i in n:
		var ang: float = passo / 2.0 - s.cone_width / 2.0 + i * passo
		var v: float = leituras[i]
		var d: float = (1.0 - v) * s.ray_length if v > 0.0 else -1.0
		print("%3d  %+7.1f   %6.3f   %s" % [
			i, ang, v, ("%.1f m" % d) if d >= 0.0 else "nada"])
	get_tree().quit()
