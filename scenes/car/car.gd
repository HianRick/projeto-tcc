extends RigidBody3D
class_name Car

var track: Track

## Parametros em grandezas reais (m/s^2, km/h, g, metros). A escala foi
## escolhida para esta pista: 694 m de extensao, 8 m de largura util e curva
## mais fechada de ~4 m de raio - dimensoes de kart, nao de formula.

@export_group("Motor e freios")
## Velocidade de pico. O arrasto e calculado para que ela seja atingida
## exatamente quando o empuxo se iguala a resistencia.
@export var top_speed_kmh := 120.0
## Aceleracao longitudinal com acelerador cheio.
@export var acceleration_ms2 := 8.0
## Frenagem com o pedal cheio. Fica abaixo do teto do pneu (grip_g x 9,81),
## senao frear no limite zeraria toda a aderencia lateral disponivel.
@export var braking_ms2 := 14.0
## Desaceleracao ao soltar o acelerador (freio-motor e atrito de rolamento).
@export var engine_brake_ms2 := 3.0
## Fracao da aceleracao disponivel em marcha a re.
@export var reverse_ratio := 0.3

@export_group("Aderencia")
## Aceleracao que os pneus sustentam, em g. E um orcamento UNICO, dividido
## entre longitudinal e lateral pelo circulo de tracao: gastar aderencia
## freando tira aderencia para curvar. E esse acoplamento que faz existir uma
## trajetoria de menor tempo diferente do caminho mais curto.
@export var grip_g := 1.5
## Esterco maximo das rodas dianteiras. Com entre-eixos de 1,2 m, 30 graus dao
## raio minimo de giro de 2,1 m - suficiente para a curva de 4 m da pista.
@export var max_steer_angle_deg := 30.0
## Velocidade com que o volante gira ao esterçar. Com 30 graus de esterço
## maximo, 90 graus/s dao um terco de segundo de batente a batente - da para
## dosar o angulo no meio do caminho, em vez de ser tudo ou nada.
@export var steer_rate_deg := 90.0
## Volta ao centro e mais rapida que a ida, como num volante com caster: os
## pneus tendem a se realinhar sozinhos quando se alivia a direcao.
@export var steer_return_rate_deg := 170.0

## Quao rapido a taxa de guinada pode mudar, em rad/s^2. Representa a inercia
## de rotacao do carro: recuperar aderencia devolve curva de uma vez, mas o
## carro nao consegue passar a girar mais rapido no mesmo instante.
@export var yaw_accel_max := 6.0

@export_group("Geometria")
## Distancia entre eixos. Junto com o esterco, define o raio minimo de giro.
## Confere com a posicao das rodas no modelo: 0,801 no arquivo x 1,5 de escala.
@export var wheelbase_m := 1.2
## Raio da roda. So afeta o visual: define a que velocidade elas giram.
@export var wheel_radius_m := 0.21

@export_group("Recompensa")
## Penalidade terminal ao bater. O padrao e zero de proposito: encerrar o
## episodio ja e a punicao, porque o agente perde todo o progresso que ainda
## faria. Como progresso so soma, qualquer avanco antes da batida rende mais
## que ficar parado - e e esse o gradiente que faltava. Um valor alto demais
## aqui recria a timidez: se bater cedo ficar pior que nao sair do lugar, a
## politica volta a escolher a imobilidade.
@export var penalidade_por_batida := 0.0

@onready var ai_controller: CarAIController = $CarAIController
@onready var raycast_sensor_wall: RayCastSensor3D = $RayCastSensorWall
@onready var camera: Camera3D = $"Camera3D"
@onready var cronometro: Cronometro = $Cronometro

# As rodas sao nodes separados no modelo, entao da para esterçar e girar cada
# uma. Busca por nome porque o importador de glTF insere um node intermediario
# com nome gerado, que tornaria o caminho fixo fragil.
var _rodas: Array[Node3D] = []
var _rodas_dianteiras: Array[Node3D] = []
var _giro_da_roda := 0.0

var ui: UI

## Definidos pelo CarAIController. Acelerador e freio sao independentes: da
## para segurar um resto de freio entrando na curva (trail braking), e e o
## circulo de tracao que arbitra o que sobra de aderencia lateral.
var requested_throttle: float
var requested_brake: float
var requested_steering: float

## Angulo atual das rodas, em radianos. E estado: nao muda instantaneamente.
var steering_angle := 0.0
## Curso de volante que ainda produz efeito na velocidade atual. Acima disso o
## pneu satura e girar mais o volante nao fecha mais a curva. Serve para o
## comando do jogador e do agente cobrir a faixa util inteira.
var esterco_util := 0.0

# Calculados em _physics_process e aplicados em _integrate_forces.
var _target_yaw_rate := 0.0
var _long_accel := 0.0
## Quanto do orcamento de aderencia sobrou para o lado depois do que o
## acelerador e o freio consumiram. Em m/s^2.
var _lateral_disponivel := 0.0

## Posicao ao longo da curva da pista, em metros. E o que sobrou do antigo
## sistema de voltas: serve so para a recompensa de progresso.
var track_length: float
var previous_offset: float
var current_offset: float
var _quadro_do_offset := -1

## Segundos de contagem regressiva antes de liberar o carro.
var seconds_until_race_begins: int
var training_mode: bool

## Contagem de contatos com muro. E instrumentacao: o cronometro le para
## registrar quantos toques houve em cada volta.
var toques_no_muro := 0

## Levantada pelo sinal de colisao e consumida no proximo passo de fisica.
var _bateu := false

var initial_transform: Transform3D
var _just_reset: bool


func _ready():
	var modelo: Node3D = $car_base
	for nome in ["wheelFrontLeft", "wheelFrontRight", "wheelBackLeft", "wheelBackRight"]:
		var roda: Node3D = modelo.find_child(nome, true, false)
		assert(roda != null, "roda '%s' nao encontrada no modelo do carro" % nome)
		_rodas.append(roda)
	_rodas_dianteiras = [_rodas[0], _rodas[1]]

	ai_controller.init(self)
	initial_transform = global_transform
	track_length = track.track_path.curve.get_baked_length()
	update_track_related_data()
	cronometro.iniciar()


func reset():
	global_transform = initial_transform

	# Precisa reancorar o progresso na linha de largada. Sem isto, o primeiro
	# get_reward apos o reset compara a posicao nova com a de onde o episodio
	# terminou e entrega uma recompensa enorme e falsa.
	update_track_related_data()
	previous_offset = current_offset
	if cronometro != null:
		cronometro.reiniciar_volta()

	if not training_mode:
		if camera.current:
			ui.show_get_ready_text(seconds_until_race_begins)

		process_mode = Node.PROCESS_MODE_DISABLED
		await get_tree().create_timer(seconds_until_race_begins, true, true).timeout
		process_mode = Node.PROCESS_MODE_INHERIT

	_just_reset = true
	_bateu = false

func _integrate_forces(state: PhysicsDirectBodyState3D):
	if _just_reset:
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		state.transform = initial_transform
		steering_angle = 0.0
		esterco_util = deg_to_rad(max_steer_angle_deg)
		_target_yaw_rate = 0.0
		_long_accel = 0.0
		_lateral_disponivel = grip_g * 9.81
		_just_reset = false
		return

	var basis_atual := state.transform.basis
	var v_local := basis_atual.inverse() * state.linear_velocity

	# A guinada vem da geometria da direcao, nao de um torque livre. E por isso
	# que o carro deixa de girar parado: sem velocidade, nao ha guinada.
	#
	# Mas ela nao muda de um frame para o outro: o carro tem inercia de rotacao.
	# Sem este limite, soltar o freio no meio da curva devolvia aderencia de
	# uma vez e a taxa de giro saltava mais de tres vezes num unico passo de
	# fisica - o carro parecia ser arremessado para o lado.
	var guinada_atual := state.angular_velocity.y
	var guinada_nova := move_toward(
		guinada_atual, _target_yaw_rate, yaw_accel_max * state.step
	)
	state.angular_velocity = Vector3(0.0, guinada_nova, 0.0)

	# Forca longitudinal: acelerador, freio e arrasto ja combinados.
	state.apply_central_force(basis_atual.z * _long_accel * mass)

	# Aderencia lateral: anula a deriva, mas so ate o que sobrou do orcamento
	# depois do acelerador e do freio. Frear forte deixa pouco para o lado, e o
	# carro sai de frente - o comportamento que obriga a frear antes da curva.
	var forca_para_anular_deriva := -v_local.x * mass / state.step
	var teto_de_aderencia := _lateral_disponivel * mass
	state.apply_central_force(
		basis_atual.x * clampf(forca_para_anular_deriva, -teto_de_aderencia, teto_de_aderencia)
	)


func _physics_process(delta):
	# Bater e falhar: o episodio acaba ali. Tratado aqui, e nao dentro do sinal
	# de colisao, porque teletransportar um corpo durante o callback de fisica
	# da resultado indefinido.
	#
	# Isto tambem resolve o disparo repetido: antes, um carro encostado no muro
	# reemitia body_entered dezenas de vezes por segundo e acumulava penalidade
	# sem limite. Agora o primeiro toque termina o episodio, e so ha um evento.
	if _bateu:
		_bateu = false
		if ai_controller.heuristic != "human":
			_end_episode(-penalidade_por_batida)
			return

	# Sem sistema de voltas, o episodio do agente termina por limite de passos
	# (reset_after no CarAIController). Isso vale so para o RL: quando e voce
	# dirigindo, o carro nunca e teleportado de volta para a largada.
	if ai_controller.needs_reset and ai_controller.heuristic != "human":
		_end_episode()

	var acelerador := 0.0
	var freio := 0.0
	var comando_volante := 0.0

	# Sempre, para o cronometro e a recompensa nao dependerem de quem esta
	# dirigindo. O cache acima evita recalcular quando as observacoes pedirem.
	update_track_related_data()

	if ai_controller.heuristic == "human":
		if Input.is_action_pressed("move_forward"):
			acelerador = 1.0
		if Input.is_action_pressed("move_backward"):
			freio = 1.0

		if Input.is_action_pressed("steer_left"):
			comando_volante += 1.0
		if Input.is_action_pressed("steer_right"):
			comando_volante -= 1.0
	else:
		acelerador = requested_throttle
		freio = requested_brake
		comando_volante = requested_steering

	var v_local := global_transform.basis.inverse() * linear_velocity
	var velocidade_frontal := v_local.z

	# Direcao sensivel a velocidade. Sem isto, a 90 km/h bastariam 1,6 dos 30
	# graus de curso para saturar o pneu: 5% do volante faria tudo e os outros
	# 95% nada, deixando a direcao com resposta de liga/desliga. Limitando o
	# curso ao que a aderencia comporta, o comando volta a ser proporcional em
	# toda a faixa, em qualquer velocidade.
	esterco_util = deg_to_rad(max_steer_angle_deg)
	var v_abs := absf(velocidade_frontal)
	if v_abs > 1.0:
		# Esterco que levaria a guinada exatamente ao limite de aderencia.
		var guinada_no_limite := (grip_g * 9.81) / v_abs
		esterco_util = minf(esterco_util, atan(guinada_no_limite * wheelbase_m / v_abs))

	# O volante tem inercia propria: gira a uma taxa limitada ate o alvo. Aliviar
	# ou inverter a direcao usa a taxa de retorno, mais rapida que a de esterco.
	var alvo := comando_volante * esterco_util
	var aliviando := absf(alvo) < absf(steering_angle) or signf(alvo) != signf(steering_angle)
	var taxa: float = steer_return_rate_deg if aliviando else steer_rate_deg
	# A taxa acompanha o curso util: o tempo de percorrer a faixa inteira fica
	# constante, em vez de o volante cruzar um curso minusculo num piscar.
	var proporcao := esterco_util / deg_to_rad(max_steer_angle_deg)
	steering_angle = move_toward(steering_angle, alvo, deg_to_rad(taxa) * proporcao * delta)

	# Ackermann: a guinada e consequencia do esterco e da velocidade.
	var guinada := tan(steering_angle) * velocidade_frontal / wheelbase_m

	# Circulo de tracao. O pneu tem um orcamento unico; o que o acelerador e o
	# freio consomem no sentido longitudinal deixa de estar disponivel no lado:
	#
	#     a_lateral = sqrt( (grip * g)^2 - a_longitudinal^2 )
	#
	var orcamento := grip_g * 9.81
	var a_pneu := _aceleracao_do_pneu(acelerador, freio, velocidade_frontal)
	_lateral_disponivel = sqrt(maxf(0.0, orcamento * orcamento - a_pneu * a_pneu))

	# A guinada possivel cai junto, porque a_lateral = v * omega.
	var guinada_maxima := _lateral_disponivel / maxf(absf(velocidade_frontal), 0.5)
	_target_yaw_rate = clampf(guinada, -guinada_maxima, guinada_maxima)

	# O arrasto aerodinamico nao passa pelo pneu, entao entra depois do circulo.
	_long_accel = a_pneu - _arrasto(velocidade_frontal)

	_animar_rodas(delta, velocidade_frontal)


## Puramente visual. A ordem de Euler do Godot e YXZ, entao o esterco (Y) fica
## por fora e o giro (X) por dentro - que e exatamente como uma roda funciona.
func _animar_rodas(delta: float, velocidade: float):
	_giro_da_roda = wrapf(_giro_da_roda + velocidade / wheel_radius_m * delta, -TAU, TAU)
	for roda in _rodas:
		roda.rotation = Vector3(_giro_da_roda, 0.0, 0.0)
	for roda in _rodas_dianteiras:
		roda.rotation = Vector3(_giro_da_roda, steering_angle, 0.0)


## Aceleracao transmitida pelo contato do pneu com o asfalto. E so esta parcela
## que disputa o orcamento de aderencia - o arrasto aerodinamico fica de fora.
func _aceleracao_do_pneu(acelerador: float, freio: float, velocidade: float) -> float:
	var a := 0.0
	var parado := absf(velocidade) < 0.5

	if freio > 0.01:
		if parado:
			# Freio com o carro parado engata a re.
			a = -freio * acceleration_ms2 * reverse_ratio
		else:
			# Freio sempre se opoe ao movimento, indo para frente ou de re.
			a = -signf(velocidade) * freio * braking_ms2

	if acelerador > 0.01:
		a += acelerador * acceleration_ms2

	if absf(a) < 0.01:
		# Pedais soltos: freio-motor, sempre contra o movimento.
		a = -signf(velocidade) * engine_brake_ms2 * minf(absf(velocidade), 1.0)

	return a


## Arrasto proporcional a v^2, calibrado para que empuxo e resistencia se
## igualem exatamente em top_speed_kmh. A velocidade maxima passa a ser
## consequencia da fisica em vez de um numero arbitrario.
func _arrasto(velocidade: float) -> float:
	var v_max := top_speed_kmh / 3.6
	var k := acceleration_ms2 / (v_max * v_max)
	return k * velocidade * absf(velocidade)


## Updates any data needed before the AI controller sends observations
func prepare_for_sending_obs():
	update_track_related_data()


## A projecao na curva e cara, entao o resultado vale por quadro de fisica:
## quem pedir primeiro calcula, os demais reaproveitam. Antes isto so rodava
## quando havia humano dirigindo ou quando o agente pedia observacoes, o que
## deixava current_offset parado em qualquer outro caso - e o cronometro, que
## depende dele, falhava em silencio.
func update_track_related_data():
	var quadro := Engine.get_physics_frames()
	if quadro == _quadro_do_offset:
		return
	_quadro_do_offset = quadro
	current_offset = track.track_path.curve.get_closest_offset(global_position)


func update_reward():
	var offset_difference = current_offset - previous_offset

	if offset_difference > (track_length / 2.0):
		offset_difference = offset_difference - track_length

	if offset_difference < -(track_length / 2.0):
		offset_difference = offset_difference + track_length

	## Reward for moving along the track (positive or negative depending on direction)
	ai_controller.reward += offset_difference / 10.0

	## Backward movement penalty
	ai_controller.reward += min(0.0, get_normalized_velocity_in_player_reference().z + 0.1) * 5.0

	previous_offset = current_offset


func get_next_track_points(num_points: int, step_size: float) -> Array:
	var temp_array: Array[float] = []
	var closest_offset = current_offset

	for i in range(0, num_points):
		var current_point = track.track_path.curve.sample_baked(
			fmod(closest_offset + step_size * (i + 1), track_length)
		)
		var local = to_local(current_point) / (num_points * step_size)
		temp_array.append_array([local.x, local.z])
	return temp_array


func _end_episode(final_reward: float = 0.0):
	ai_controller.reward += final_reward
	ai_controller.done = true
	ai_controller.reset()
	reset()


func get_normalized_velocity_in_player_reference():
	# Normaliza pela velocidade de pico, com folga, para a observacao nao saturar.
	var escala := (top_speed_kmh / 3.6) * 1.2
	return (global_transform.basis.inverse() * linear_velocity).limit_length(escala) / escala


func _on_body_entered(_body):
	toques_no_muro += 1
	_bateu = true
