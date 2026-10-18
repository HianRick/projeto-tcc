extends Node3D
const Pistas := preload("res://scenes/track/pistas.gd")
## Exporta a linha central da pista amostrada, para analise fora do Godot.

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

	var curva: Curve3D = gs.get_node("Track").track_path.curve
	# O bake_interval do projeto e grosso (0,5 m) de proposito, para acelerar o
	# get_closest_offset do treino. Para medir curvatura isso vira degrau: os
	# pontos caem sobre segmentos retos. Reamostra fino so para esta exportacao.
	curva.bake_interval = 0.02
	var L := curva.get_baked_length()
	print("TRACKLEN %f" % L)
	# Grava em arquivo: imprimir dezenas de milhares de linhas no console e
	# ordens de grandeza mais lento que escreve-las, e para um circuito de 4 km
	# isso domina o tempo de execucao.
	var destino := "C:/tcc/treinos/tracado.txt"
	for a in OS.get_cmdline_args():
		if a.begins_with("--saida="):
			destino = a.split("=")[1]
	var f := FileAccess.open(destino, FileAccess.WRITE)
	f.store_line("TRACKLEN %f" % L)
	var s := 0.0
	while s < L:
		var p := curva.sample_baked(s)
		f.store_line("P %f %f %f" % [s, p.x, p.z])
		s += 0.05
	f.close()
	print("GRAVADO %s  (%.1f m)" % [destino, L])
	get_tree().quit()
