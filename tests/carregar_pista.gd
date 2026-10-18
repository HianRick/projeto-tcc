extends Node3D
const Pistas := preload("res://scenes/track/pistas.gd")
## Verificacao leve: carrega a cena com a pista pedida e relata a geometria.

func _ready():
	var t0 := Time.get_ticks_msec()
	var gs: Node3D = load("res://scenes/game_scene/game_scene.tscn").instantiate()
	gs.get_node("Sync").control_mode = 0
	var cars = gs.get_node("Cars")
	cars.training_mode = true
	cars.number_of_cars_to_spawn = 1
	cars.ui = gs.get_node("UI")
	gs.get_node("Track").training_mode = true
	Pistas.aplicar(gs)
	add_child(gs)
	var curva: Curve3D = gs.get_node("Track").track_path.curve
	print("CARREGOU em %.1f s | pontos=%d | extensao=%.1f m" % [
		(Time.get_ticks_msec() - t0) / 1000.0, curva.point_count,
		curva.get_baked_length()])
	get_tree().quit()
