extends Node3D
const Pistas := preload("res://scenes/track/pistas.gd")

## TRAINING     - varios carros em paralelo, controlados pelo Python via TCP.
## INFERENCE    - um carro, dirigido por um modelo .onnx ja treinado.
## TEST_DRIVE   - um carro, dirigido por voce no teclado.
## HEURISTICA   - um carro, dirigido pela trajetoria calculada (sem aprendizado).
enum GameModes { TRAINING, INFERENCE, TEST_DRIVE, HEURISTICA }
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
			"heuristica":
				return GameModes.HEURISTICA
			_:
				push_warning("--modo desconhecido; usando o valor da cena")
	return -1


func _ready():
	var da_linha := _modo_da_linha_de_comando()
	if da_linha >= 0:
		game_mode = da_linha
	print("[GameManager] modo: %s" % GameModes.keys()[game_mode])

	var new_game_scene: Node3D = game_scene.instantiate()
	# Antes de qualquer configuracao: o Track e o CarManager leem a curva no
	# _ready, que so dispara ao entrar na arvore.
	Pistas.aplicar(new_game_scene)
	var sync = new_game_scene.get_node("Sync")
	var cars = new_game_scene.get_node("Cars") as CarManager
	var track = new_game_scene.get_node("Track") as Track

	# Menos carros deixam a mensagem trocada com o Python menor e o bloqueio da
	# engine mais curto, o que torna a observacao visual utilizavel.
	for argumento in OS.get_cmdline_args():
		if argumento.begins_with("--carros="):
			cars.number_of_cars_to_spawn = maxi(1, int(argumento.split("=")[1]))

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
		GameModes.HEURISTICA:
			sync.control_mode = sync.ControlModes.HUMAN
			cars.training_mode = false
			sync.speed_up = 1.0
	add_child(new_game_scene)

	if game_mode == GameModes.HEURISTICA:
		_instalar_piloto(cars)
	if "--sensores" in OS.get_cmdline_args():
		_mostrar_sensores(cars)

	# A camera livre e instrumentacao de observacao: so aparece com --assistir e
	# nao altera fisica, observacoes nem recompensa.
	if "--assistir" in OS.get_cmdline_args():
		_criar_camera_livre(new_game_scene, cars)


## Desenha os raios do sensor de parede de cada veiculo. Instrumentacao de
## observacao: nao altera fisica, observacoes nem recompensa.
func _mostrar_sensores(cars: CarManager):
	var script := load("res://scenes/car/sensor_visual.gd")
	var n := 0
	for c in cars.get_children():
		if c is Car:
			var visual = script.new()
			visual.instalar(c.raycast_sensor_wall)
			n += 1
	print("[Sensores] desenhando os raios de %d veiculo(s)" % n)


## Troca os pontos da linha central, nas observacoes do agente, pelos pontos
## da trajetoria calculada. E a condicao experimental de RL com heuristica.
func _instalar_trajetoria_de_referencia(cars: CarManager):
	var caminho := ""
	## --linha_obs substitui os pontos da linha central; --linha_desvio
	## acrescenta o deslocamento lateral como observacao propria.
	var aditivo := false
	for argumento in OS.get_cmdline_args():
		if argumento.begins_with("--linha_obs="):
			caminho = argumento.split("=")[1]
			aditivo = false
		elif argumento.begins_with("--linha_desvio="):
			caminho = argumento.split("=")[1]
			aditivo = true
	if caminho.is_empty():
		return

	var traj = load("res://scenes/car/trajetoria.gd").new()
	if not traj.carregar(caminho):
		return
	for c in cars.get_children():
		if c is Car:
			if aditivo:
				c.trajetoria_desvio = traj
			else:
				c.trajetoria_referencia = traj
	var modo := "desvio lateral como observacao adicional" if aditivo else "referencia geometrica substituida"
	print("[Observacoes] %s (%d pontos)" % [modo, traj.pontos()])


## Carrega a trajetoria calculada e entrega aos carros. O caminho vem de
## --linha=<arquivo>; sem ele, o modo nao tem o que seguir.
func _instalar_piloto(cars: CarManager):
	var caminho := ""
	for argumento in OS.get_cmdline_args():
		if argumento.begins_with("--linha="):
			caminho = argumento.split("=")[1]
	if caminho.is_empty():
		push_error("modo heuristica exige --linha=<arquivo.csv>")
		return

	var piloto = load("res://scenes/car/piloto_heuristico.gd").new()
	if not piloto.carregar(caminho):
		return
	for c in cars.get_children():
		if c is Car:
			c.piloto_heuristico = piloto


func _criar_camera_livre(cena: Node3D, cars: CarManager):
	var camera := CameraLivre.new()
	camera.name = "CameraLivre"
	camera.far = 2000.0
	cena.add_child(camera)

	# Comeca acima do centro do circuito, olhando para baixo em diagonal. O
	# enquadramento vem da extensao do tracado, para servir a qualquer pista.
	var caixa := Pistas.centro_e_raio(cena)
	var centro: Vector3 = caixa[0]
	var raio: float = maxf(caixa[1], 1.0)
	camera.far = maxf(2000.0, raio * 8.0)
	camera.global_position = centro + Vector3(0.0, raio * 1.1, raio * 1.0)
	camera.look_at(centro, Vector3.UP)
	camera.rotation = Vector3(camera.rotation.x, camera.rotation.y, 0.0)

	var lista: Array[Node3D] = []
	for c in cars.get_children():
		if c is Car:
			lista.append(c)
	camera.definir_carros(lista, cars.player_controlled)

	var mover := "IJKL" if cars.player_controlled else "WASD"
	var vertical := "U/O" if cars.player_controlled else "Q/E"
	print(("[CameraLivre] setas olham, %s move, %s desce e sobe, Shift acelera, " +
		"Tab segue um carro, C volta para a camera do carro (%d carros)") % [
		mover, vertical, lista.size()])
