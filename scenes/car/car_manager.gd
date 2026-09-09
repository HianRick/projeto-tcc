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


func spawn_cars(quantidade: int):
	if not training_mode:
		quantidade = 1

	for car_id in range(0, quantidade):
		var car = car_scene.instantiate() as Car
		car.name = "AI-%d" % car_id
		car.track = track

		# Os carros so enxergam as paredes (camada 1). Todos ficam na camada 2 e
		# nenhum tem a camada 2 na mascara, entao eles se atravessam: cada um
		# treina como se estivesse sozinho na pista.
		car.set_collision_layer_value(2, true)
		car.set_collision_mask_value(1, true)

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

		car.ai_controller.track = track
		car.reset()
