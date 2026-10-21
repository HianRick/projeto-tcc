extends Node3D

class_name CarManager

@export var track: Track
@export var car_scene: PackedScene

## Quantos carros treinam em paralelo na mesma pista. Fora do treino, e sempre
## um so. Como os carros nao colidem entre si (ver spawn_cars), esse numero nao
## esbarra no limite de camadas de fisica do Godot.
@export var number_of_cars_to_spawn: int = 14

var ui: UI

var training_mode: bool = true
## Quando verdadeiro, o unico carro da cena responde ao teclado.
var player_controlled: bool = false
var seconds_until_race_begins: int


# Called when the node enters the scene tree for the first time.
func _ready():
	spawn_cars(number_of_cars_to_spawn)


## Abertura do leque de raios, em graus. Zero mantem o valor da cena.
## Existe para o experimento de redistribuicao angular: o exemplo de origem
## usa 360 graus porque tinha adversario e bonificacoes ao redor, mas numa
## prova contra o relogio quase metade dos raios olha para tras, e o vao
## entre raios vizinhos a frente chega a 7 m a vinte metros de distancia.
var _cone_do_sensor := 0.0


func _carregar_trajetoria(caminho: String):
	if caminho.is_empty():
		return null
	var t = load("res://scenes/car/trajetoria.gd").new()
	if not t.carregar(caminho):
		return null
	print("[Observacoes] trajetoria carregada: %s (%d pontos)" % [caminho, t.pontos()])
	return t


func spawn_cars(quantidade: int):
	if not training_mode:
		quantidade = 1

	var caminho_obs := ""
	var caminho_desvio := ""
	for argumento in OS.get_cmdline_args():
		if argumento.begins_with("--cone="):
			_cone_do_sensor = float(argumento.split("=")[1])
		elif argumento.begins_with("--linha_obs="):
			caminho_obs = argumento.split("=")[1]
		elif argumento.begins_with("--linha_desvio="):
			caminho_desvio = argumento.split("=")[1]

	# A trajetoria precisa estar instalada ANTES do _ready do Sync, que e quem
	# negocia o tamanho do vetor de observacoes com o processo de treinamento.
	# Instalada depois, a rede nasce com 27 entradas e passa a receber 30.
	var traj_obs = _carregar_trajetoria(caminho_obs)
	var traj_desvio = _carregar_trajetoria(caminho_desvio)

	for car_id in range(0, quantidade):
		var car = car_scene.instantiate() as Car
		car.name = "AI-%d" % car_id
		car.track = track

		# Os carros so enxergam as paredes (camada 1). Todos ficam na camada 2 e
		# nenhum tem a camada 2 na mascara, entao eles se atravessam: cada um
		# treina como se estivesse sozinho na pista.
		car.set_collision_layer_value(2, true)
		car.set_collision_mask_value(1, true)

		# Antes de entrar na arvore: e no _ready do sensor que os raios nascem.
		if _cone_do_sensor > 0.0:
			var sensor = car.get_node("RayCastSensorWall")
			sensor.cone_width = _cone_do_sensor
			if car_id == 0:
				print("[Sensor] cone de %.0f graus, passo de %.1f graus" % [
					_cone_do_sensor, _cone_do_sensor / sensor.n_rays_width])

		var car_transform: Transform3D = track.track_path.curve.sample_baked_with_rotation(0.0)
		car_transform = car_transform.rotated_local(Vector3.UP, PI)
		# Meia altura do carro (0,30 m) mais a espessura do asfalto (0,10 m), para
		# as rodas pousarem na pista em vez de flutuarem como o hovercraft.
		car_transform.origin += Vector3.UP * 0.4
		car.global_transform = car_transform

		car.ui = ui
		car.seconds_until_race_begins = seconds_until_race_begins
		car.training_mode = training_mode

		var car_body: MeshInstance3D = car.find_child("body", true, false) as MeshInstance3D
		var new_material: StandardMaterial3D = (
			car_body.get_active_material(1).duplicate() as StandardMaterial3D
		)
		new_material.albedo_color = Color.from_hsv(randf_range(0, 1), 0.6, 0.6)
		car_body.set_surface_override_material(1, new_material)

		add_child(car)

		# Fora do treino ha um carro so, e e ele que a camera acompanha - seja
		# voce dirigindo ou o agente.
		if not training_mode:
			car.get_node("Camera3D").current = true
			if ui != null:
				ui.carro_observado = car

		if player_controlled:
			car.name = "Player"
			# O plugin separa os agentes por control_mode: marcar este como HUMAN
			# faz o sync deixar a heuristica dele em "human".
			car.ai_controller.control_mode = AIController3D.ControlModes.HUMAN

		car.trajetoria_referencia = traj_obs
		car.trajetoria_desvio = traj_desvio

		car.ai_controller.track = track
		car.reset()
