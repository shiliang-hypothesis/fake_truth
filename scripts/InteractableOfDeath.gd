class_name InteractableOfDeath
extends Area2D

signal interacted

func _init() -> void:
	collision_layer = 0
	# 死亡世界交互物：只检测死亡形态的玩家。
	# 层号约定见 scripts/BodyMasker.gd —— 层4 = dead_player（位值 8）。
	collision_mask = 8

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
 
func interact() -> void:
	print("[Interact] %s" %name)
	interacted.emit()

func _on_body_entered(player: Player) -> void:
	player.register_interactable_of_death(self)

func _on_body_exited(player: Player) -> void:
	player.unregister_interactable_of_death(self)
