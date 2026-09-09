extends Node3D
## Verifica o cronometro contra um valor conhecido.
##
## Em vez de pilotar, arrasta o carro ao longo da curva a uma velocidade fixa.
## Assim o tempo de volta correto e simplesmente comprimento / velocidade, e da
## para conferir a cronometragem sem depender da qualidade de nenhum piloto.

const VELOCIDADE := 20.0  # m/s
const VOLTAS_ALVO := 3

var carro: Car
var curva: Curve3D
var _distancia := 0.0


func _ready():
	var gs: Node3D = load("res://scenes/game_scene/game_scene.tscn").instantiate()
	var sync = gs.get_node("Sync")
	sync.control_mode = sync.ControlModes.HUMAN
	var cars = gs.get_node("Cars")
	cars.number_of_cars_to_spawn = 1
	cars.training_mode = true
	gs.get_node("Track").training_mode = true
	add_child(gs)

	carro = cars.get_node("AI-0")
	carro.ai_controller.heuristic = "model"
	# Sem reposicionamento por limite de passos, que cortaria a volta ao meio.
	carro.ai_controller.reset_after = 99999999
	# Congela a fisica: aqui a posicao e imposta, nao simulada.
	carro.freeze = true
	curva = carro.track.track_path.curve

	print("comprimento da pista: %.2f m" % carro.track_length)
	print("velocidade imposta:   %.2f m/s" % VELOCIDADE)
	print("tempo de volta esperado: %.3f s" % (carro.track_length / VELOCIDADE))
	print("")


func _physics_process(delta):
	_distancia += VELOCIDADE * delta
	var pose := curva.sample_baked_with_rotation(fmod(_distancia, carro.track_length))
	pose = pose.rotated_local(Vector3.UP, PI)
	pose.origin += Vector3.UP * 0.4
	carro.global_transform = pose

	if carro.cronometro.voltas_completas >= VOLTAS_ALVO:
		var esperado := carro.track_length / VELOCIDADE
		var erro := (carro.cronometro.melhor_tempo - esperado) / esperado * 100.0
		print("")
		print("melhor volta medida: %.3f s   (esperado %.3f s, erro %+.2f%%)" % [
			carro.cronometro.melhor_tempo, esperado, erro])
		print("SONDA_CONCLUIDA")
		get_tree().quit()
