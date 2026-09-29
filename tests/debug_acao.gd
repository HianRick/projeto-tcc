extends Node3D
## Mostra o que a politica esta recebendo e o que esta mandando para o carro.

var carro: Car
var t := 0.0
var n := 0


func _ready():
	var gs: Node3D = load("res://scenes/game_scene/game_scene.tscn").instantiate()
	var sync = gs.get_node("Sync")
	sync.control_mode = sync.ControlModes.ONNX_INFERENCE
	sync.deterministic_inference = not ("--amostrar" in OS.get_cmdline_args())
	print("deterministic_inference = %s" % sync.deterministic_inference)
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
	carro.ai_controller.reset_after = 99999999


func _physics_process(delta):
	if carro == null:
		return
	t += delta
	n += 1
	if n % 30 != 0:
		return
	var obs: Array = carro.ai_controller.get_obs_for_car(carro)
	var v: float = (carro.global_transform.basis.inverse() * carro.linear_velocity).z
	print("t=%5.2f  acel=%+.3f freio=%+.3f volante=%+.3f  v=%5.1f km/h  obs[0..3]=%s  raio_frente=%.3f" % [
		t, carro.requested_throttle, carro.requested_brake, carro.requested_steering,
		v * 3.6, str(obs.slice(0, 4)).left(60), obs[14]])
	if n == 30:
		print("OBS27 %s" % ",".join(obs.map(func(x): return "%.6f" % x)))
	if t > 3.0:
		get_tree().quit()
