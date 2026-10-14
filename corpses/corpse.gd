# Corpse.gd
extends RigidBody2D

## 尸体只是"属于实类世界的物品"。
## 它的碰撞层、和谁碰撞、在哪个世界可见/冻结，全部由 real_body 标签 + BodyMasker 推导，
## 所以这个脚本里不需要出现任何 layer / mask / visible / freeze 的字样。
##
## 以后要让尸体变成灵魂世界的物品，只需要把标签从 real_body 换成 dead_body ——
## 碰撞、可见性、冻结、以及"谁还能推它"会全部自动跟着变。

@onready var tags: TagComponent = $TagComponent

func _ready() -> void:
	tags.add_tag("real_body")
	# ★ "可推"是同一种物理性质：摩擦降为 0，靠 linear_damp 滑一段就停。
	#   默认摩擦 1.0 会吃掉小冲量，表现为"贴上去推不动"。
	#   放在这里（而不是场景文件里），让"可推物品"的定义集中在这一个脚本。
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	physics_material_override = material

## 被玩家 / 其它同世界的东西推开：先叫醒沉睡刚体，再施加冲量。
## 推不是"推尸体"的特判 —— 谁有 push() 谁就能被推（见 player.gd 的 apply_push）。
func push(impulse: Vector2) -> void:
	if sleeping:
		sleeping = false      # 沉睡的刚体会忽略小冲量，先叫醒
	apply_central_impulse(impulse)
