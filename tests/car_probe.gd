extends Node3D
## Sonda de fisica: dirige o carro por codigo e imprime as medidas, para
## conferir se o comportamento bate com os parametros declarados em car.gd.
##
## Rodar com:
##   Godot.exe --headless --path <projeto> res://tests/car_probe.tscn --fixed-fps 500 --disable-render-loop

enum Fase { ACELERACAO, FRENAGEM, ADERENCIA, CIRCULO, TRANSIENTE, LINEARIDADE, VOLANTE, FIM }

const DURACAO_ACELERACAO := 14.0
## Tempo para o volante assumir a posicao antes de comecar a medir.
const ASSENTAMENTO := 0.5
const JANELA_MEDIDA := 0.6
## Na prova do circulo a velocidade cai rapido, entao a janela e mais curta.
const JANELA_CIRCULO := 0.3

var carro: Car
var fase: int = Fase.ACELERACAO
var t := 0.0
var relogio_total := 0.0
var proximo_print := 1.0

var v_inicial_freio := 0.0
var pos_inicial_freio := Vector3.ZERO

var velocidades_alvo := [30.0, 60.0, 90.0, 120.0]
var idx_alvo := 0
var medindo := false
var yaw_inicial := 0.0
var soma_v := 0.0
var n_amostras := 0

## Fracoes de freio testadas na prova do circulo de tracao.
var fracoes_de_freio := [0.0, 0.25, 0.5, 0.75, 1.0]
var idx_fracao := 0
const V_CIRCULO := 90.0
var v_ini_circ := 0.0

var medindo_ida := true

## Prova do transiente: solta o freio no meio da curva e grava quadro a quadro.
var fase_transiente := 0
var amostras_transiente: Array = []

## Prova de linearidade: fracoes de volante e a curva que cada uma entrega.
var fracoes_de_volante := [0.25, 0.5, 0.75, 1.0]
var idx_volante := 0


func _ready():
	var cena_jogo: Node3D = load("res://scenes/game_scene/game_scene.tscn").instantiate()

	var sync = cena_jogo.get_node("Sync")
	sync.control_mode = sync.ControlModes.HUMAN

	var cars = cena_jogo.get_node("Cars")
	cars.number_of_cars_to_spawn = 1
	cars.training_mode = true
	cena_jogo.get_node("Track").training_mode = true

	add_child(cena_jogo)

	carro = cars.get_node("AI-0")
	# "model" faz o carro obedecer requested_*, em vez de ler o teclado.
	carro.ai_controller.heuristic = "model"
	# Atravessa os muros: aqui interessa a fisica do carro, nao a pista.
	carro.collision_mask = 0

	var raio_min: float = carro.wheelbase_m / tan(deg_to_rad(carro.max_steer_angle_deg))
	print("")
	print("parametros declarados:")
	print("  pico %.0f km/h | acel %.1f m/s2 | freio %.1f m/s2" % [
		carro.top_speed_kmh, carro.acceleration_ms2, carro.braking_ms2])
	print("  orcamento de aderencia %.2f g = %.2f m/s2  (unico, dividido pelo circulo)" % [
		carro.grip_g, carro.grip_g * 9.81])
	print("  esterco %.0f graus | entre-eixos %.2f m | raio minimo de giro %.2f m" % [
		carro.max_steer_angle_deg, carro.wheelbase_m, raio_min])

	var n_obs: int = carro.ai_controller.get_obs()["obs"].size()
	var acoes: Dictionary = carro.ai_controller.get_action_space()
	print("  interface de RL: %d observacoes, acoes %s" % [n_obs, ", ".join(acoes.keys())])
	print("")
	print("--- aceleracao (acelerador cheio a partir do zero) ---")


func _velocidade() -> float:
	return (carro.global_transform.basis.inverse() * carro.linear_velocity).z


func _pedais(acelerador: float, freio: float, volante: float):
	carro.requested_throttle = acelerador
	carro.requested_brake = freio
	carro.requested_steering = volante


## Arrasto aerodinamico previsto, para separa-lo do que o pneu entregou.
func _arrasto(v: float) -> float:
	var v_max: float = carro.top_speed_kmh / 3.6
	var k: float = carro.acceleration_ms2 / (v_max * v_max)
	return k * v * absf(v)


func _physics_process(delta):
	if fase == Fase.FIM:
		return

	relogio_total += delta
	if relogio_total > 150.0:
		print("SONDA_ABORTADA: excedeu 150 s de tempo simulado na fase %d" % fase)
		fase = Fase.FIM
		get_tree().quit(1)
		return

	t += delta

	match fase:
		Fase.ACELERACAO:
			_pedais(1.0, 0.0, 0.0)
			if t >= proximo_print:
				print("  t=%4.1fs  %6.1f km/h" % [t, _velocidade() * 3.6])
				proximo_print += 1.0
			if t >= DURACAO_ACELERACAO:
				v_inicial_freio = _velocidade() * 3.6
				pos_inicial_freio = carro.global_position
				fase = Fase.FRENAGEM
				print("")
				print("--- frenagem (freio cheio a partir de %.1f km/h) ---" % v_inicial_freio)
				t = 0.0

		Fase.FRENAGEM:
			_pedais(0.0, 1.0, 0.0)
			if _velocidade() * 3.6 <= 0.5:
				var distancia := carro.global_position.distance_to(pos_inicial_freio)
				print("  parou em %.2f s e %.1f m" % [t, distancia])
				print("  desaceleracao media: %.1f m/s2" % ((v_inicial_freio / 3.6) / t))
				print("")
				print("--- aderencia lateral (volante cheio, pedais soltos) ---")
				print("  %10s %12s %10s %12s" % ["velocidade", "giro", "raio", "acel.lateral"])
				fase = Fase.ADERENCIA
				t = 0.0
				medindo = false

		Fase.ADERENCIA:
			_pedais(0.0, 0.0, 1.0)
			if not medindo:
				var alvo_ms: float = velocidades_alvo[idx_alvo] / 3.6
				carro.linear_velocity = carro.global_transform.basis.z * alvo_ms
				if t >= ASSENTAMENTO:
					medindo = true
					t = 0.0
					yaw_inicial = carro.global_rotation.y
					soma_v = 0.0
					n_amostras = 0
			else:
				soma_v += absf(_velocidade())
				n_amostras += 1
				if t >= JANELA_MEDIDA:
					var giro: float = absf(wrapf(carro.global_rotation.y - yaw_inicial, -PI, PI)) / t
					var v_media: float = soma_v / maxf(n_amostras, 1)
					var raio: float = v_media / giro if giro > 0.001 else INF
					print("  %7.0f km/h %8.3f rad/s %8.1f m %10.2f g" % [
						v_media * 3.6, giro, raio, (v_media * giro) / 9.81])
					idx_alvo += 1
					medindo = false
					t = 0.0
					if idx_alvo >= velocidades_alvo.size():
						print("")
						print("--- circulo de tracao (volante cheio + freio parcial, a %.0f km/h) ---"
							% V_CIRCULO)
						print("  freio  %10s %10s %10s %10s %10s" % [
							"a.long", "a.lat", "a.lat prev", "soma", "orcamento"])
						fase = Fase.CIRCULO
						t = 0.0
						medindo = false

		Fase.CIRCULO:
			var fracao: float = fracoes_de_freio[idx_fracao]
			_pedais(0.0, fracao, 1.0)

			if not medindo:
				carro.linear_velocity = carro.global_transform.basis.z * (V_CIRCULO / 3.6)
				if t >= ASSENTAMENTO:
					medindo = true
					t = 0.0
					yaw_inicial = carro.global_rotation.y
					v_ini_circ = _velocidade()
					soma_v = 0.0
					n_amostras = 0
			else:
				soma_v += absf(_velocidade())
				n_amostras += 1
				if t >= JANELA_CIRCULO:
					var v_media: float = soma_v / maxf(n_amostras, 1)
					var giro: float = absf(wrapf(carro.global_rotation.y - yaw_inicial, -PI, PI)) / t
					var a_lat: float = v_media * giro
					# O que o pneu entregou no sentido longitudinal, ja descontado
					# o arrasto aerodinamico, que nao passa pelo contato.
					var a_long: float = absf((_velocidade() - v_ini_circ) / t) - _arrasto(v_media)
					var orcamento: float = carro.grip_g * 9.81
					var prev: float = sqrt(maxf(0.0, orcamento * orcamento - a_long * a_long))
					print("  %4.0f%%  %8.2f g %8.2f g %8.2f g %8.2f g %8.2f g" % [
						fracao * 100.0, a_long / 9.81, a_lat / 9.81, prev / 9.81,
						sqrt(a_long * a_long + a_lat * a_lat) / 9.81, orcamento / 9.81])
					idx_fracao += 1
					medindo = false
					t = 0.0
					if idx_fracao >= fracoes_de_freio.size():
						print("")
						print("--- transiente ao soltar o freio no meio da curva (90 km/h) ---")
						fase = Fase.TRANSIENTE
						fase_transiente = 0
						t = 0.0

		Fase.TRANSIENTE:
			if fase_transiente == 0:
				# Estabiliza curvando com freio cheio.
				carro.linear_velocity = carro.global_transform.basis.z * (V_CIRCULO / 3.6)
				_pedais(0.0, 1.0, 1.0)
				if t >= 0.8:
					fase_transiente = 1
					t = 0.0
					amostras_transiente.clear()
			else:
				# Solta o freio de uma vez e grava a taxa de giro.
				_pedais(0.0, 0.0, 1.0)
				amostras_transiente.append(absf(carro.angular_velocity.y))
				if t >= 0.5:
					var passo := 1.0 / 60.0
					print("  quadro   tempo   taxa de giro    variacao")
					var ant: float = amostras_transiente[0]
					for i in range(0, mini(amostras_transiente.size(), 13)):
						var g: float = amostras_transiente[i]
						print("  %5d  %6.3fs   %8.3f rad/s  %+8.3f" % [
							i, i * passo, g, g - ant])
						ant = g
					var total: float = amostras_transiente[mini(12, amostras_transiente.size() - 1)] - amostras_transiente[0]
					print("  variacao total em 0,2 s: %+.3f rad/s" % total)
					print("")
					print("--- linearidade da direcao (a %.0f km/h, pedais soltos) ---" % V_CIRCULO)
					print("  volante  %12s %12s %14s" % ["giro", "acel.lateral", "proporcional?"])
					fase = Fase.LINEARIDADE
					t = 0.0
					medindo = false

		Fase.LINEARIDADE:
			var fv: float = fracoes_de_volante[idx_volante]
			_pedais(0.0, 0.0, fv)
			if not medindo:
				carro.linear_velocity = carro.global_transform.basis.z * (V_CIRCULO / 3.6)
				if t >= ASSENTAMENTO:
					medindo = true
					t = 0.0
					yaw_inicial = carro.global_rotation.y
					soma_v = 0.0
					n_amostras = 0
			else:
				soma_v += absf(_velocidade())
				n_amostras += 1
				if t >= JANELA_CIRCULO:
					var giro: float = absf(wrapf(carro.global_rotation.y - yaw_inicial, -PI, PI)) / t
					var v_med: float = soma_v / maxf(n_amostras, 1)
					var lat: float = v_med * giro / 9.81
					# Com direcao proporcional, a aceleracao lateral deve seguir a
					# fracao de volante. Saturada, todas dariam o mesmo valor.
					print("  %5.0f%%  %8.3f rad/s %9.2f g %12.0f%%" % [
						fv * 100.0, giro, lat, 100.0 * lat / 1.46])
					idx_volante += 1
					medindo = false
					t = 0.0
					if idx_volante >= fracoes_de_volante.size():
						print("")
						print("--- volante (tempo de curso) ---")
						carro.steering_angle = 0.0
						carro.linear_velocity = Vector3.ZERO
						fase = Fase.VOLANTE
						medindo_ida = true
						t = 0.0

		Fase.VOLANTE:
			var limite := deg_to_rad(carro.max_steer_angle_deg)
			if medindo_ida:
				_pedais(0.0, 0.0, 1.0)
				if carro.steering_angle >= limite * 0.999:
					print("  centro ate fim de curso (%.0f graus): %.3f s" % [
						carro.max_steer_angle_deg, t])
					medindo_ida = false
					t = 0.0
			else:
				_pedais(0.0, 0.0, 0.0)
				if carro.steering_angle <= limite * 0.001:
					print("  fim de curso de volta ao centro:     %.3f s" % t)
					print("")
					print("SONDA_CONCLUIDA")
					fase = Fase.FIM
					get_tree().quit()
