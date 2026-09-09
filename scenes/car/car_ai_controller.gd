extends AIController3D
class_name CarAIController

var track: Track


## Observacoes (27 no total):
##   3  velocidade longitudinal, lateral e taxa de guinada
##   1  angulo atual das rodas
##   6  tres pontos seguintes da pista, no referencial do carro
##  17  raios do sensor de parede
func get_obs_for_car(car: Car):
	var player_velocity = car.get_normalized_velocity_in_player_reference()
	var observations: Array = [player_velocity.x, player_velocity.z, car.angular_velocity.y / 5.0]

	# O volante tem inercia, entao o angulo atual e estado. Sem esta observacao
	# o agente decide sem saber para onde as rodas ja estao apontadas.
	# Normaliza pelo curso util na velocidade atual, e nao pelo curso mecanico,
	# para a observacao cobrir [-1, 1] em qualquer velocidade.
	observations.append(car.steering_angle / maxf(car.esterco_util, 0.001))

	observations.append_array(car.get_next_track_points(3, 20))
	observations.append_array(car.raycast_sensor_wall.get_observation())
	return observations


func get_obs() -> Dictionary:
	_player.prepare_for_sending_obs()
	return {"obs": get_obs_for_car(_player)}


func get_reward() -> float:
	_player.update_reward()
	return reward


## Acelerador e freio sao eixos separados para que o agente possa segurar um
## resto de freio entrando na curva. Ambos sao contínuos em [-1, 1] porque e o
## que o PPO produz; a metade negativa e tratada como pedal solto.
func get_action_space() -> Dictionary:
	return {
		"throttle": {"size": 1, "action_type": "continuous"},
		"brake": {"size": 1, "action_type": "continuous"},
		"steering": {"size": 1, "action_type": "continuous"},
	}


func set_action(action) -> void:
	_player.requested_throttle = clampf(action.throttle[0], 0.0, 1.0)
	_player.requested_brake = clampf(action.brake[0], 0.0, 1.0)
	_player.requested_steering = clampf(action.steering[0], -1.0, 1.0)
