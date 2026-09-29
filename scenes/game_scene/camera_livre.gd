extends Camera3D
class_name CameraLivre
## Camera de observacao livre, para acompanhar o treino visualmente.
##
## Nao participa da simulacao: nao altera fisica, observacoes nem recompensa.
## Existe apenas quando o simulador e iniciado com a flag --assistir.
##
## O sync do plugin pausa a arvore de cena a cada troca de mensagem com o
## processo Python. Por isso esta camera roda em PROCESS_MODE_ALWAYS: sem isso
## ela congelaria junto com o resto durante as pausas, que sao a maior parte do
## tempo de relogio em treino.
##
## Controles:
##   setas                   olhar ao redor (funciona sempre)
##   botao direito do mouse  olhar com o mouse (falha durante o treino,
##                           quando a engine fica bloqueada na rede)
##   W A S D                 mover no plano
##   Q / E                   descer / subir
##   Shift                   acelerar o movimento
##   roda do mouse           ajustar a velocidade base
##   Tab                     alternar entre camera livre e seguir um carro
##   1 .. 9                  escolher qual carro seguir

@export var velocidade := 12.0
@export var sensibilidade := 0.003
@export var multiplicador_turbo := 4.0

var _olhando := false
var _giro := Vector2.ZERO
var _seguindo: Node3D = null
var _carros: Array[Node3D] = []
var _indice_carro := 0


func _ready():
	# A arvore fica pausada a maior parte do tempo durante o treino.
	process_mode = Node.PROCESS_MODE_ALWAYS
	current = true
	_giro = Vector2(rotation.y, rotation.x)


func definir_carros(lista: Array):
	_carros.clear()
	for c in lista:
		_carros.append(c)


func _unhandled_input(evento):
	if evento is InputEventMouseButton:
		if evento.button_index == MOUSE_BUTTON_RIGHT:
			_olhando = evento.pressed
			Input.mouse_mode = (
				Input.MOUSE_MODE_CAPTURED if _olhando else Input.MOUSE_MODE_VISIBLE
			)
		elif evento.pressed and evento.button_index == MOUSE_BUTTON_WHEEL_UP:
			velocidade = minf(velocidade * 1.15, 400.0)
		elif evento.pressed and evento.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			velocidade = maxf(velocidade / 1.15, 2.0)

	elif evento is InputEventMouseMotion and _olhando:
		_giro.x -= evento.relative.x * sensibilidade
		_giro.y = clampf(_giro.y - evento.relative.y * sensibilidade, -1.5, 1.5)
		rotation = Vector3(_giro.y, _giro.x, 0.0)

	elif evento is InputEventKey and evento.pressed and not evento.echo:
		if evento.keycode == KEY_TAB:
			_alternar_perseguicao()
		elif evento.keycode >= KEY_1 and evento.keycode <= KEY_9:
			_indice_carro = evento.keycode - KEY_1
			_seguindo = _carro_valido(_indice_carro)


func _alternar_perseguicao():
	if _seguindo != null:
		_seguindo = null
		return
	_seguindo = _carro_valido(_indice_carro)


func _carro_valido(i: int) -> Node3D:
	if i < 0 or i >= _carros.size():
		return null
	var c: Node3D = _carros[i]
	return c if is_instance_valid(c) else null


func _process(delta_bruto):
	# Durante o treino a engine fica bloqueada esperando o Python, entao os
	# quadros chegam esparsos e com delta enorme. Sem teto, cada quadro faria a
	# camera saltar dezenas de metros.
	var delta: float = minf(delta_bruto, 1.0 / 30.0)

	# Olhar pelas setas: entrada consultada funciona mesmo com quadros raros,
	# ao contrario dos eventos de mouse, que se perdem enquanto a engine espera.
	var olhar := Vector2(
		float(Input.is_key_pressed(KEY_LEFT)) - float(Input.is_key_pressed(KEY_RIGHT)),
		float(Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_DOWN))
	)
	if olhar != Vector2.ZERO:
		_giro.x += olhar.x * 1.5 * delta
		_giro.y = clampf(_giro.y + olhar.y * 1.5 * delta, -1.5, 1.5)
		rotation = Vector3(_giro.y, _giro.x, 0.0)
		_seguindo = null

	if _seguindo != null and is_instance_valid(_seguindo):
		# Acompanha por tras e um pouco acima, sem herdar a rotacao do carro.
		var atras := _seguindo.global_transform.basis.z * -9.0 + Vector3.UP * 4.0
		global_position = global_position.lerp(_seguindo.global_position + atras, 0.12)
		look_at(_seguindo.global_position + Vector3.UP * 0.8, Vector3.UP)
		_giro = Vector2(rotation.y, rotation.x)
		return

	var direcao := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		direcao -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		direcao += global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		direcao -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		direcao += global_transform.basis.x
	if Input.is_key_pressed(KEY_E):
		direcao += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		direcao -= Vector3.UP

	if direcao == Vector3.ZERO:
		return

	var v := velocidade
	if Input.is_key_pressed(KEY_SHIFT):
		v *= multiplicador_turbo
	global_position += direcao.normalized() * v * delta
