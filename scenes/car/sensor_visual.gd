extends MeshInstance3D
## Desenha os raios do sensor de parede, exatamente como o agente os percebe.
##
## Nao refaz a consulta de colisao: le o proprio vetor de observacoes e
## reconstroi o ponto atingido a partir dele. O que aparece na tela e,
## portanto, o dado que entra na rede - e nao uma medicao paralela que
## poderia divergir dela.
##
## A normalizacao do sensor e (alcance - distancia) / alcance, de modo que 0
## significa "nada encontrado dentro do alcance" e 1 significa "encostado".
## Note que "nada" e "parede exatamente no alcance maximo" produzem o mesmo
## valor; aqui os dois casos sao desenhados em cinza.
##
## Puramente visual: nao altera fisica, observacoes nem recompensa.

## Da verde (longe) a vermelho (perto).
const COR_LONGE := Color(0.25, 0.95, 0.35, 0.85)
const COR_PERTO := Color(1.0, 0.25, 0.2, 0.95)
const COR_SEM_ALVO := Color(0.45, 0.45, 0.5, 0.35)

var _sensor: RayCastSensor3D
var _malha := ImmediateMesh.new()
var _ja_relatou := false


func instalar(sensor: RayCastSensor3D) -> void:
	_sensor = sensor
	mesh = _malha

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Sem teste de profundidade os raios aparecem por cima do asfalto, em vez
	# de sumirem dentro dele.
	m.no_depth_test = true
	m.render_priority = 1
	material_override = m

	sensor.add_child(self)
	position = Vector3.ZERO
	# O sync do plugin pausa a arvore a cada troca de mensagem com o processo
	# Python, e durante a inferencia ONNX tambem. Sem PROCESS_MODE_ALWAYS os
	# raios congelariam junto - o mesmo motivo pelo qual a camera livre roda
	# sempre.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(_delta) -> void:
	if _sensor == null or _sensor.rays.is_empty():
		return

	var leituras: Array = _sensor.get_observation()
	var alcance: float = _sensor.ray_length

	_malha.clear_surfaces()
	_malha.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in mini(leituras.size(), _sensor.rays.size()):
		var direcao: Vector3 = _sensor.rays[i].target_position.normalized()
		var valor: float = leituras[i]

		var ponta: Vector3
		var cor: Color
		if valor <= 0.0:
			ponta = direcao * alcance
			cor = COR_SEM_ALVO
		else:
			ponta = direcao * ((1.0 - valor) * alcance)
			cor = COR_LONGE.lerp(COR_PERTO, clampf(valor, 0.0, 1.0))

		_malha.surface_set_color(cor)
		_malha.surface_add_vertex(Vector3.ZERO)
		_malha.surface_set_color(cor)
		_malha.surface_add_vertex(ponta)
	_malha.surface_end()

	if not _ja_relatou:
		_ja_relatou = true
		print("[SensorVisual] %d raios, alcance %.0f m" % [leituras.size(), alcance])
