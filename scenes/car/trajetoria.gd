extends RefCounted
## Trajetoria calculada por train/linha_otima.py, carregada como dado.
##
## Serve a dois usos distintos: o piloto heuristico a segue, e o agente de
## Aprendizado por Reforco pode receber seus pontos como observacao, no lugar
## dos pontos da linha central. No segundo caso nada mais muda - mesma
## arquitetura, mesma recompensa, mesmo numero de observacoes. Apenas a
## informacao disponivel e outra.
##
## A indexacao e pela posicao na LINHA CENTRAL, porque e essa a projecao que o
## veiculo ja mantem (current_offset). Os pontos estao espacados uniformemente
## ao longo dela, entao localizar-se nao exige busca.

var _x := PackedFloat64Array()
var _z := PackedFloat64Array()
var _v := PackedFloat64Array()
## Deslocamento lateral em relacao a linha central, com sinal: positivo para a
## esquerda do sentido de percurso.
var _alfa := PackedFloat64Array()
var _n := 0
var _ds := 1.0


func carregar(caminho: String) -> bool:
	if not FileAccess.file_exists(caminho):
		push_error("trajetoria nao encontrada: %s" % caminho)
		return false

	var f := FileAccess.open(caminho, FileAccess.READ)
	f.get_line()  # cabecalho
	var s0 := 0.0
	var s1 := 0.0
	while not f.eof_reached():
		var linha := f.get_line().strip_edges()
		if linha.is_empty():
			continue
		var c := linha.split(",")
		if c.size() < 6:
			continue
		if _n == 0:
			s0 = float(c[0])
		elif _n == 1:
			s1 = float(c[0])
		_x.append(float(c[1]))
		_z.append(float(c[2]))
		_alfa.append(float(c[3]))
		_v.append(float(c[5]))
		_n += 1
	f.close()

	if _n < 3:
		push_error("trajetoria com poucos pontos: %s" % caminho)
		return false
	_ds = maxf(s1 - s0, 0.001)
	return true


func pontos() -> int:
	return _n


## Ponto da trajetoria correspondente a uma posicao na linha central.
func em(s_central: float) -> Vector3:
	var i := int(round(s_central / _ds)) % _n
	if i < 0:
		i += _n
	return Vector3(_x[i], 0.0, _z[i])


## Deslocamento lateral da trajetoria, em metros, na posicao pedida.
func desvio_em(s_central: float) -> float:
	var i := int(round(s_central / _ds)) % _n
	if i < 0:
		i += _n
	return _alfa[i]


func velocidade_em(s_central: float) -> float:
	var i := int(round(s_central / _ds)) % _n
	if i < 0:
		i += _n
	return _v[i]
