extends Node3D

## TRAINING     - varios carros em paralelo, controlados pelo Python via TCP.
## INFERENCE    - um carro, dirigido por um modelo .onnx ja treinado.
## TEST_DRIVE   - um carro, dirigido por voce no teclado.
enum GameModes { TRAINING, INFERENCE, TEST_DRIVE }
@export var game_mode: GameModes = GameModes.TEST_DRIVE
@export var game_scene: PackedScene

@export var seconds_until_race_begins: int = 3


## O modo pode vir da linha de comando, o que permite exportar um binario
## unico e escolher o comportamento na hora de executar:
##   --modo=training | inference | test_drive
func _modo_da_linha_de_comando() -> int:
	for argumento in OS.get_cmdline_args():
		if not argumento.begins_with("--modo="):
			continue
		match argumento.split("=")[1].to_lower():
			"training":
				return GameModes.TRAINING
			"inference":
				return GameModes.INFERENCE
			"test_drive":
				return GameModes.TEST_DRIVE
			_:
				push_warning("--modo desconhecido; usando o valor da cena")
	return -1


func _ready():
	var da_linha := _modo_da_linha_de_comando()
	if da_linha >= 0:
		game_mode = da_linha
	print("[GameManager] modo: %s" % GameModes.keys()[game_mode])

	var new_game_scene: Node3D = game_scene.instantiate()
	var sync = new_game_scene.get_node("Sync")
	var cars = new_game_scene.get_node("Cars") as CarManager
	var track = new_game_scene.get_node("Track") as Track

	cars.ui = new_game_scene.get_node("UI") as UI
	cars.seconds_until_race_begins = seconds_until_race_begins

	match game_mode:
		GameModes.TRAINING:
			sync.control_mode = sync.ControlModes.TRAINING
			track.training_mode = true
			sync.speed_up = 20.0
		GameModes.INFERENCE:
			sync.control_mode = sync.ControlModes.ONNX_INFERENCE
			cars.training_mode = false
			sync.speed_up = 1.0
		GameModes.TEST_DRIVE:
			# Sem rede e sem modelo: o sync fica so olhando.
			sync.control_mode = sync.ControlModes.HUMAN
			cars.training_mode = false
			cars.player_controlled = true
			sync.speed_up = 1.0
	add_child(new_game_scene)
