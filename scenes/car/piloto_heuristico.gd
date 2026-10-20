extends RefCounted
## Piloto heuristico: segue a trajetoria calculada por train/linha_otima.py.
##
## Nao ha aprendizado aqui. O solver determina, fora da simulacao, por onde
## passar e a que velocidade; este controlador apenas transforma isso nos tres
## mesmos comandos de que o agente dispoe - acelerador, freio e esterco.
##
## Direcao por perseguicao pura: mira um ponto da trajetoria a frente e calcula
## o esterco que levaria ate ele.
##
## Pedais por antecipacao mais correcao. O perfil de velocidade nao diz apenas
## a que velocidade passar, mas tambem, por sua propria derivada, que
## aceleracao e necessaria em cada ponto. Comandar essa aceleracao diretamente,
## invertendo o modelo do veiculo, evita o atraso estrutural de um controlador
## apenas proporcional - que so reage depois que o erro ja apareceu.
##
## Localizar o carro na trajetoria nao exige busca: o veiculo ja conhece a
## propria projecao na linha central (current_offset), e os pontos da
## trajetoria estao espacados uniformemente ao longo dela.

## Quantos segundos a frente mirar. Curto demais, o carro serpenteia; longo
## demais, ele corta as curvas por dentro.
var OLHAR_SEGUNDOS := 0.55
const OLHAR_MINIMO := 4.0
const OLHAR_MAXIMO := 22.0

## Antecipacao do alvo de velocidade, para cobrir o atraso de atuacao.
const ANTECIPAR_SEGUNDOS := 0.25

## Correcao proporcional sobre o erro de velocidade, em m/s^2 por m/s.
const GANHO_VELOCIDADE := 2.5

## Ganho da correcao de desvio lateral. Entra dividido pela velocidade, de modo
## que a correcao seja suave em alta e firme em baixa.
## Correcao de desvio lateral, em rad/s por metro de erro.
var GANHO_LATERAL := 0.35
## Correcao de erro de rumo, em rad/s por radiano de erro.
var GANHO_RUMO := 1.60
## Antecipacao da curvatura, casada com o tempo que o volante leva para
## percorrer o curso util (cerca de um terco de segundo).
var ANTECIPAR_CURVA := 0.15

var _x := PackedFloat64Array()
var _z := PackedFloat64Array()
var _v := PackedFloat64Array()
## Aceleracao longitudinal exigida pelo perfil em cada ponto, em m/s^2.
var _a := PackedFloat64Array()
## Curvatura com sinal do caminho, e a tangente unitaria, em cada ponto.
var _k := PackedFloat64Array()
var _tx := PackedFloat64Array()
var _tz := PackedFloat64Array()
var _n := 0
var _ds := 1.0


func carregar(caminho: String) -> bool:
	if not FileAccess.file_exists(caminho):
		push_error("trajetoria nao encontrada: %s" % caminho)
		return false

	var f := FileAccess.open(caminho, FileAccess.READ)
	f.get_line()  # cabecalho
	var s_primeiro := 0.0
	var s_segundo := 0.0
	while not f.eof_reached():
		var linha := f.get_line().strip_edges()
		if linha.is_empty():
			continue
		var c := linha.split(",")
		if c.size() < 6:
			continue
		if _n == 0:
			s_primeiro = float(c[0])
		elif _n == 1:
			s_segundo = float(c[0])
		_x.append(float(c[1]))
		_z.append(float(c[2]))
		_v.append(float(c[5]))
		_n += 1
	f.close()

	if _n < 3:
		push_error("trajetoria com poucos pontos: %s" % caminho)
		return false
	_ds = maxf(s_segundo - s_primeiro, 0.001)
	_calcular_aceleracoes()
	_calcular_geometria()
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--olhar="):
			OLHAR_SEGUNDOS = float(arg.split("=")[1])
		elif arg.begins_with("--glat="):
			GANHO_LATERAL = float(arg.split("=")[1])
		elif arg.begins_with("--grumo="):
			GANHO_RUMO = float(arg.split("=")[1])
		elif arg.begins_with("--antecurva="):
			ANTECIPAR_CURVA = float(arg.split("=")[1])

	print("[Heuristica] %d pontos, espacamento %.2f m, velocidade %.1f a %.1f km/h" % [
		_n, _ds, _menor(_v) * 3.6, _maior(_v) * 3.6])
	return true


## a = v * dv/ds, medida ao longo do proprio caminho - nao da linha central,
## porque os espacamentos diferem onde a trajetoria se afasta do centro.
func _calcular_aceleracoes() -> void:
	_a.resize(_n)
	for i in _n:
		var j := (i + 1) % _n
		var comprimento := Vector2(_x[j] - _x[i], _z[j] - _z[i]).length()
		if comprimento < 0.001:
			_a[i] = 0.0
		else:
			_a[i] = _v[i] * (_v[j] - _v[i]) / comprimento


## Curvatura com sinal e tangente do caminho. O sinal segue a regra da mao
## direita em torno de Y, que e a mesma do comando de esterco: positivo vira a
## esquerda.
func _calcular_geometria() -> void:
	_k.resize(_n)
	_tx.resize(_n)
	_tz.resize(_n)
	for i in _n:
		var ant := (i - 1 + _n) % _n
		var prox := (i + 1) % _n
		var d1 := Vector2(_x[i] - _x[ant], _z[i] - _z[ant])
		var d2 := Vector2(_x[prox] - _x[i], _z[prox] - _z[i])
		var corda := Vector2(_x[prox] - _x[ant], _z[prox] - _z[ant])

		var t := corda.normalized()
		_tx[i] = t.x
		_tz[i] = t.y

		var cruz := d1.y * d2.x - d1.x * d2.y
		var denom := d1.length() * d2.length() * corda.length()
		_k[i] = 0.0 if denom < 1e-9 else 2.0 * cruz / denom


func _menor(a: PackedFloat64Array) -> float:
	var m := a[0]
	for x in a:
		m = minf(m, x)
	return m


func _maior(a: PackedFloat64Array) -> float:
	var m := a[0]
	for x in a:
		m = maxf(m, x)
	return m


## Calcula os comandos e os deposita no carro, no mesmo formato que o agente
## usa. O resto do modelo dinamico segue identico.
func dirigir(carro: Car) -> void:
	var v_atual: float = (carro.global_transform.basis.inverse() * carro.linear_velocity).z
	var v_abs := absf(v_atual)
	var i := int(round(carro.current_offset / _ds)) % _n

	# --- direcao: antecipacao de curvatura mais correcao ----------------
	# A perseguicao pura sozinha corta as curvas: o erro de regime vale cerca
	# de Ld^2/8R, o que numa curva de 20 m com 11 m de mira passa de 70 cm.
	# Antecipar a curvatura do proprio caminho elimina esse vies, e a correcao
	# passa a tratar so o desvio residual.
	# O controle e formulado em TAXA DE GUINADA, nao em angulo de esterco. O
	# curso util do volante encolhe com a velocidade - a 72 km/h sao 2,5 graus
	# -, entao somar termos de correcao em radianos satura o comando quase
	# sempre. Taxa de guinada e a grandeza que a fisica limita, e sobre ela os
	# ganhos tem significado direto.
	var base := carro.global_transform
	var para_esquerda := base.basis.x
	var para_frente := base.basis.z

	var ff := (i + int(round(ANTECIPAR_CURVA * v_abs / _ds))) % _n
	var guinada := v_atual * _k[ff]

	var desvio := base.origin - Vector3(_x[i], base.origin.y, _z[i])
	var erro_lateral := desvio.dot(para_esquerda)
	var tangente := Vector3(_tx[i], 0.0, _tz[i])
	var erro_rumo := atan2(tangente.dot(para_esquerda), tangente.dot(para_frente))

	guinada += GANHO_RUMO * erro_rumo - GANHO_LATERAL * erro_lateral
	var esterco := atan(guinada * carro.wheelbase_m / maxf(v_abs, 1.0))
	carro.requested_steering = clampf(
		esterco / maxf(carro.esterco_util, 0.001), -1.0, 1.0
	)

	# --- pedais: antecipacao mais correcao -----------------------------
	var k := (i + int(round(ANTECIPAR_SEGUNDOS * v_abs / _ds))) % _n
	var desejada := _a[k] + GANHO_VELOCIDADE * (_v[k] - v_atual)
	_aplicar_aceleracao(carro, desejada, v_atual)


## Inverte o modelo longitudinal do veiculo: dada a aceleracao liquida desejada,
## determina a posicao dos pedais que a produz.
func _aplicar_aceleracao(carro: Car, desejada: float, v: float) -> void:
	# O arrasto nao passa pelo pneu, entao o pedal precisa cobri-lo alem da
	# aceleracao pedida.
	var v_max := carro.top_speed_kmh / 3.6
	var arrasto := (carro.acceleration_ms2 / (v_max * v_max)) * v * absf(v)
	var no_pneu := desejada + arrasto

	if no_pneu > 0.0:
		carro.requested_throttle = clampf(no_pneu / carro.acceleration_ms2, 0.0, 1.0)
		carro.requested_brake = 0.0
		return

	# Desacelerando. O freio-motor ja entrega parte do retardo de graca; so o
	# que passar dele precisa de pedal.
	var freio_motor := carro.engine_brake_ms2 * minf(absf(v), 1.0)
	if -no_pneu <= freio_motor:
		carro.requested_throttle = 0.0
		carro.requested_brake = 0.0
	else:
		carro.requested_throttle = 0.0
		carro.requested_brake = clampf(-no_pneu / carro.braking_ms2, 0.0, 1.0)
