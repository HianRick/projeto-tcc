extends Control
class_name UI

@export var get_ready: Label
@export var cronometro_label: Label

## Preenchido pelo CarManager com o carro que a camera acompanha.
var carro_observado: Car


func _process(_delta):
	if cronometro_label == null or carro_observado == null:
		return
	var c: Cronometro = carro_observado.cronometro
	var melhor := "--:--" if c.melhor_tempo == INF else _mmss(c.melhor_tempo)
	cronometro_label.text = "volta %d   melhor %s   ultima %s" % [
		c.voltas_completas + 1, melhor,
		"--:--" if c.ultimo_tempo == 0.0 else _mmss(c.ultimo_tempo)]


func _mmss(segundos: float) -> String:
	return "%d:%05.2f" % [int(segundos) / 60, fmod(segundos, 60.0)]



func show_get_ready_text(seconds_remaining: int):
	get_ready.visible = true
	for seconds in range(seconds_remaining, 0, -1):
		get_ready.text = "Comecando em: %d" % seconds
		await get_tree().create_timer(1, true, true).timeout
	deactivate_get_ready_text()


func deactivate_get_ready_text():
	get_ready.visible = false
