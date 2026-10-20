extends Node3D
const Pistas := preload("res://scenes/track/pistas.gd")
## Renderiza a pista vista de cima e grava um PNG.
##
## Precisa de renderizador de verdade, entao NAO use --headless.
##   Godot.exe --path <proj> res://tests/foto_pista.tscn --pista=<nome> \
##             --saida=C:/caminho/foto.png

func _ready():
	var gs: Node3D = load("res://scenes/game_scene/game_scene.tscn").instantiate()
	gs.get_node("Sync").control_mode = 0
	var cars = gs.get_node("Cars")
	cars.training_mode = true
	cars.number_of_cars_to_spawn = 1
	cars.ui = gs.get_node("UI")
	# Por padrao sem decoracao, como nas sondas de medida. Com --decorado,
	# reproduz o que aparece em dirigir.bat e assistir.bat.
	gs.get_node("Track").training_mode = not ("--decorado" in OS.get_cmdline_args())
	Pistas.aplicar(gs)
	add_child(gs)

	# --sensores desenha os raios; --carro enquadra no veiculo em vez do circuito.
	var carro: Car = null
	for c in cars.get_children():
		if c is Car:
			carro = c
			break
	if "--sensores" in OS.get_cmdline_args() and carro != null:
		var visual = load("res://scenes/car/sensor_visual.gd").new()
		visual.instalar(carro.raycast_sensor_wall)

	var caixa := Pistas.centro_e_raio(gs)
	var centro: Vector3 = caixa[0]
	var raio: float = maxf(caixa[1], 1.0)

	var cam := Camera3D.new()
	cam.far = raio * 10.0
	add_child(cam)
	# De cima, olhando para baixo. +X fica a direita e -Z para cima da tela,
	# que e a orientacao de um mapa com o norte para cima.
	cam.global_position = centro + Vector3(0.0, raio * 2.4, 0.0)
	cam.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	cam.current = true

	if "--carro" in OS.get_cmdline_args() and carro != null:
		centro = carro.global_position
		raio = 30.0

	var destino := "C:/tcc/treinos/foto.png"
	var zoom := 1.0
	for a in OS.get_cmdline_args():
		if a.begins_with("--saida="):
			destino = a.split("=")[1]
		elif a.begins_with("--zoom="):
			zoom = float(a.split("=")[1])
	cam.global_position = centro + Vector3(0.0, raio * 2.4 / zoom, 0.0)

	# O chao da cena original foi dimensionado para a pista de 694 m. Numa pista
	# maior ele vira um quadrado solto no meio do circuito.
	var chao := gs.get_node_or_null("Ground") as MeshInstance3D
	if chao != null:
		chao.global_position = Vector3(centro.x, chao.global_position.y, centro.z)
		chao.scale = Vector3.ONE * maxf(1.0, raio / 120.0)

	# Alguns quadros para a geometria CSG terminar de ser construida.
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(destino)
	print("FOTO %s" % destino)
	get_tree().quit()
