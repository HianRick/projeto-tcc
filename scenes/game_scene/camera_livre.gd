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
##   C                       voltar para a camera do carro, e de volta
##   1 .. 9                  escolher qual carro seguir
##
## Quando voce esta dirigindo, W A S D pertencem ao carro, e a camera passa a
## usar I J K L (mais U e O para descer e subir) - senao cada tecla faria as
## duas coisas ao mesmo tempo.

@export var velocidade := 12.0
@export var sensibilidade := 0.003
@export var multiplicador_turbo := 4.0

var _olhando := false
var _giro := Vector2.ZERO
var _seguindo: Node3D = null
var _carros: Array[Node3D] = []
var _indice_carro := 0
## Com piloto ao teclado, as teclas de movimento mudam para nao colidir.
var _ha_piloto := false
var _camera_do_carro: Camera3D = null


func _ready():
	# A arvore fica pausada a maior parte do tempo durante o treino.
	process_mode = Node.PROCESS_MODE_ALWAYS
	current = true
	_giro = Vector2(rotation.y, rotation.x)


func definir_carros(lista: Array, ha_piloto: bool = false):
	_carros.clear()
	for c in lista:
		_carros.append(c)
	_ha_piloto = ha_piloto
	if not _carros.is_empty():
		_camera_do_carro = _carros[0].get_node_or_null("Camera3D") as Camera3D


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



## Teclas tratadas em _input, antes da interface: o Tab e a tecla padrao de
## navegacao de foco do Godot e seria consumida pela UI da cena antes de
## chegar aqui por _unhandled_input.
func _input(evento):
	if not (evento is InputEventKey and evento.pressed and not evento.echo):
		return
	var tecla: int = evento.physical_keycode
	if tecla == 0:
		tecla = evento.keycode

	if tecla == KEY_TAB:
		_alternar_perseguicao()
	elif tecla == KEY_C:
		_alternar_camera()
	elif tecla >= KEY_1 and tecla <= KEY_9:
		_indice_carro = tecla - KEY_1
		_seguindo = _carro_valido(_indice_carro)
	else:
		return
	get_viewport().set_input_as_handled()



## Devolve o comando a camera de bordo do carro, e retoma depois.
func _alternar_camera():
	if _camera_do_carro == null:
		return
	if current:
		_camera_do_carro.current = true
	else:
		current = true


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

	# Com alguem ao volante, W A S D pertencem ao carro.
	var frente := KEY_I if _ha_piloto else KEY_W
	var tras := KEY_K if _ha_piloto else KEY_S
	var esq := KEY_J if _ha_piloto else KEY_A
	var dir := KEY_L if _ha_piloto else KEY_D
	var sobe := KEY_O if _ha_piloto else KEY_E
	var desce := KEY_U if _ha_piloto else KEY_Q

	var direcao := Vector3.ZERO
	if Input.is_key_pressed(frente):
		direcao -= global_transform.basis.z
	if Input.is_key_pressed(tras):
		direcao += global_transform.basis.z
	if Input.is_key_pressed(esq):
		direcao -= global_transform.basis.x
	if Input.is_key_pressed(dir):
		direcao += global_transform.basis.x
	if Input.is_key_pressed(sobe):
		direcao += Vector3.UP
	if Input.is_key_pressed(desce):
		direcao -= Vector3.UP

	if direcao == Vector3.ZERO:
		return

	var v := velocidade
	if Input.is_key_pressed(KEY_SHIFT):
		v *= multiplicador_turbo
	global_position += direcao.normalized() * v * delta
