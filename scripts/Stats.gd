class_name Stats
extends Node

signal health_changed(new_health: int)

@export var max_health: int = 3

var health: int = max_health:
	set(v):
		var clamped := clampi(v, 0, max_health)
		if health == clamped:
			return
		health = clamped
		health_changed.emit(health)

func reset() -> void:
	health = max_health
