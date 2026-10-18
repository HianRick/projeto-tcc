extends Node3D
class_name Track

@export var track_path: Path3D

@export_group("Checkpoint objects to add to the track:")
@export var checkpoints: Array[PackedScene]
@export var checkpoint_frequency_meters: int

@export_group("Tree objects to add to the track:")
@export var trees: Array[PackedScene]
@export var tree_frequency_meters: int

@export_group("Rock objects to add to the track:")
@export var rocks: Array[PackedScene]
@export var rock_frequency_meters: int

## Training mode disables generating decoration objects
var training_mode: bool = false

## Distancia minima entre decoracao e QUALQUER ponto da pista. Os muros ficam
## a 5 m da linha central; a folga cobre o tamanho dos objetos.
const AFASTAMENTO_MINIMO := 9.0

var _random: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var starting_line = $StartingLine

# Called when the node enters the scene tree for the first time.
func _ready():
	_random.seed = 10
	starting_line.global_transform = get_starting_position()

	if not training_mode:
		instantiate_scene_instances_on_track(checkpoints, checkpoint_frequency_meters)
		instantiate_scene_instances_on_track(trees, tree_frequency_meters, true, true)
		instantiate_scene_instances_on_track(rocks, rock_frequency_meters, true, true)


func get_starting_position() -> Transform3D:
	return track_path.curve.sample_baked_with_rotation(0.0)


func instantiate_scene_instances_on_track(
	scene: Array[PackedScene],
	frequency_meters: int,
	randomize_instances_outside_track: bool = false,
	randomize_rotation: bool = false
):
	# Lista vazia significa "nao gerar este tipo de objeto".
	if scene.is_empty() or frequency_meters <= 0:
		return

	for offset in range(frequency_meters, track_path.curve.get_baked_length(), frequency_meters):
		var instance: Node3D = scene[_random.randi_range(0, scene.size() - 1)].instantiate()
		add_child(instance)
		instance.global_transform = track_path.curve.sample_baked_with_rotation(offset)
		if randomize_instances_outside_track:
			var base := instance.global_transform
			var z_random_range: float = frequency_meters / 25.0
			var x_min_distance := 15.0
			var x_random_distance_max_offset := 5.0
			var ao_longo: Vector3 = (
				base.basis.z * _random.randf_range(-z_random_range, z_random_range)
			)
			var lateral: float = (
				x_min_distance + _random.randf_range(0.0, x_random_distance_max_offset)
			)

			# Afastar da linha central naquele ponto nao basta: no miolo de um
			# circuito, dois trechos correm paralelos, e o que esta "fora" de um
			# cai sobre o outro. Testa os dois lados contra a pista inteira e
			# descarta o objeto se nenhum servir.
			var primeiro: int = 1 if _random.randi_range(0, 1) == 0 else -1
			var posto := false
			for direction in [primeiro, -primeiro]:
				var candidato: Vector3 = (
					base.origin + ao_longo + base.basis.x * float(direction) * lateral
				)
				if _longe_da_pista(candidato):
					instance.global_transform.origin = candidato
					posto = true
					break
			if not posto:
				instance.queue_free()
				continue
		if randomize_rotation:
			instance.rotate_y(_random.randf_range(-PI, PI))


func _longe_da_pista(ponto_global: Vector3) -> bool:
	var local: Vector3 = track_path.to_local(ponto_global)
	var na_pista: Vector3 = track_path.curve.get_closest_point(local)
	return Vector2(local.x - na_pista.x, local.z - na_pista.z).length() >= AFASTAMENTO_MINIMO
