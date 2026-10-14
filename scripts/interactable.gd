class_name Interactable
extends Area2D

signal interacted

func _init() -> void:
	collision_layer = 0
	# 交互物是纯传感器：自己不占碰撞层，只检测"同一世界"的玩家进入。
	# 层号约定见 scripts/BodyMasker.gd —— 层3 = real_player（位值 4）。
	collision_mask = 4

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
 
func interact() -> void:
	print("[Interact] %s" %name)
	interacted.emit()

func _on_body_entered(player: Player) -> void:
	player.register_interactable(self)

func _on_body_exited(player: Player) -> void:
	player.unregister_interactable(self)
