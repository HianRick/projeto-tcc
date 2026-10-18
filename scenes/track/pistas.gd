extends RefCounted
## Troca o tracado do circuito por um alternativo, guardado em res://pistas/.
##
## A pista inteira - asfalto, zebras, muros e colisao - e extrudada ao longo de
## uma unica Path3D. Trocar o recurso Curve3D dessa path reconstroi tudo, entao
## nao ha cena duplicada para manter em sincronia: o tracado e um dado, nao uma
## cena.
##
## Uso:  --pista=<nome>   carrega res://pistas/<nome>.tres
##       sem o argumento, mantem o tracado original da cena.
##
## Nao declara class_name de proposito: o registro de classes globais do Godot
## so e regenerado pelo editor, e tudo aqui roda por linha de comando. Quem usa
## carrega com preload, que resolve em tempo de compilacao do script.


## Aplica o tracado pedido na linha de comando. Deve ser chamado depois de
## instanciar a game_scene e ANTES de adiciona-la a arvore, porque o Track e o
## CarManager leem a curva em _ready.
static func aplicar(cena: Node3D) -> String:
	for argumento in OS.get_cmdline_args():
		if not argumento.begins_with("--pista="):
			continue
		var nome: String = argumento.split("=")[1]
		var caminho := "res://pistas/%s.tres" % nome
		if not ResourceLoader.exists(caminho):
			push_error("pista nao encontrada: %s" % caminho)
			return ""
		var curva: Curve3D = load(caminho)
		if curva == null:
			push_error("recurso invalido (esperava Curve3D): %s" % caminho)
			return ""
		var track := cena.get_node("Track") as Track
		track.track_path.curve = curva
		_limpar_cenario_fixo(track)
		# Os portais a cada 50 m sao resto do sistema de voltas, que foi
		# removido. Atravessam a pista e nao marcam mais nada.
		track.checkpoints = []
		print("[Pistas] tracado: %s  (%d pontos, %.1f m)" % [
			nome, curva.point_count, curva.get_baked_length()])
		return nome
	return ""


## Nos estruturais da pista. Todo o resto sob o Track e decoracao posicionada
## a mao para o tracado original - casas, moinho - que em outra pista cai em
## lugar nenhum, as vezes em cima do asfalto.
const ESTRUTURAIS := [
	"EdgeLine", "Wall", "WallCollision", "CenterLine", "TrackGeometry",
	"Path", "StartingLine",
]


static func _limpar_cenario_fixo(track: Node3D) -> void:
	var removidos := 0
	for filho in track.get_children():
		if filho.name in ESTRUTURAIS:
			continue
		track.remove_child(filho)
		filho.queue_free()
		removidos += 1
	if removidos > 0:
		print("[Pistas] removidos %d objetos de cenario da pista original" % removidos)


## Caixa que envolve o tracado, para posicionar a camera livre em qualquer pista.
static func centro_e_raio(cena: Node3D) -> Array:
	var curva: Curve3D = (cena.get_node("Track") as Track).track_path.curve
	var minimo := Vector3.INF
	var maximo := -Vector3.INF
	for i in curva.point_count:
		var p := curva.get_point_position(i)
		minimo = minimo.min(p)
		maximo = maximo.max(p)
	var centro := (minimo + maximo) / 2.0
	return [centro, (maximo - minimo).length() / 2.0]
