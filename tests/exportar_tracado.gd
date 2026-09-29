extends Node3D
## Exporta a linha central da pista amostrada, para analise fora do Godot.

func _ready():
	var gs: Node3D = load("res://scenes/game_scene/game_scene.tscn").instantiate()
	gs.get_node("Sync").control_mode = 0
	var cars = gs.get_node("Cars")
	cars.training_mode = true
	cars.number_of_cars_to_spawn = 1
	cars.ui = gs.get_node("UI")
	gs.get_node("Track").training_mode = true
	add_child(gs)

	var curva: Curve3D = gs.get_node("Track").track_path.curve
	# O bake_interval do projeto e grosso (0,5 m) de proposito, para acelerar o
	# get_closest_offset do treino. Para medir curvatura isso vira degrau: os
	# pontos caem sobre segmentos retos. Reamostra fino so para esta exportacao.
	curva.bake_interval = 0.02
	var L := curva.get_baked_length()
	print("TRACKLEN %f" % L)
	var s := 0.0
	while s < L:
		var p := curva.sample_baked(s)
		print("P %f %f %f" % [s, p.x, p.z])
		s += 0.05
	get_tree().quit()
