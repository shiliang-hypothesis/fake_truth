# Rock.gd
extends RigidBody2D

## 石子是"属于实类世界的物品"，和尸体同一套身份：
## 碰撞层、和谁碰撞、在哪个世界可见/冻结，全部由 real_body 标签 + BodyMasker 推导。
##
## 比尸体多三种"能力"，每一种都是一个方法，不是类型特判：
##   · push(impulse)      —— 可被推（和尸体一样）
##   · grab(holder, hand) —— 可被捡（谁有 grab() 谁就能被捡）
##   · throw(direction)   —— 可被扔（扔出时 hitbox 上膛，砸到谁谁受伤）
##
## 以后想让灯/箱子也能被捡、被扔，实现同样的方法即可，player.gd 一行都不用改。

enum State { IDLE, HELD, THROWN }

@onready var tags: TagComponent = $TagComponent
@onready var masker: BodyMasker = $BodyMasker
@onready var hitbox: Area2D = $Hitbox

var current_state: State = State.IDLE
var _holder: Node2D = null
var _hand: Node2D = null
var _world: Node2D = null

func _ready() -> void:
	tags.add_tag("real_body")
	# "可推"是同一种物理性质：低摩擦 + linear_damp（和 corpse.gd 一致）。
	#   默认摩擦 1.0 会吃掉小冲量，表现为"贴上去推不动"。
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	physics_material_override = material
	# 扔出去的石子停稳（沉睡）后，hitbox 自动退膛，不再伤人
	sleeping_state_changed.connect(_on_sleeping_state_changed)

func _on_sleeping_state_changed() -> void:
	if sleeping and current_state == State.THROWN:
		current_state = State.IDLE
		hitbox.set_deferred("monitoring", false)

# ---- 可被推（和尸体一致）----
func push(impulse: Vector2) -> void:
	if sleeping:
		sleeping = false      # 沉睡的刚体会忽略小冲量，先叫醒
	apply_central_impulse(impulse)

# ---- 可被捡 ----
func grab(holder: Node2D, hand: Node2D) -> void:
	# 被世界冻结（不在当前世界）的物体捡不了 —— 这是规则的自然结果，不是特判
	if current_state != State.IDLE or freeze:
		return
	current_state = State.HELD
	_holder = holder
	_hand = hand
	_world = get_parent()
	# 从世界取下，挂到持有者手上，跟随移动
	_world.remove_child(self)
	hand.add_child(self)
	position = Vector2.ZERO
	freeze = true
	# 手里时不参与碰撞、不上膛，避免把持有者撞开
	collision_layer = 0
	collision_mask = 0
	hitbox.set_deferred("monitoring", false)

# ---- 放回世界（扔出 / 掉落的公共部分）----
func _release() -> void:
	var hand_pos := _hand.global_position
	var world := _world
	_hand.remove_child(self)
	world.add_child(self)
	global_position = hand_pos
	_holder = null
	_hand = null
	masker.refresh()      # 恢复 real_body 的碰撞层 + 解冻
	sleeping = false

# ---- 可被扔 ----
func throw(direction: Vector2, force: float = 400.0) -> void:
	if current_state != State.HELD:
		return
	_release()
	current_state = State.THROWN
	hitbox.set_deferred("monitoring", true)   # 上膛：飞出去的石子能砸伤生物
	apply_central_impulse(direction.normalized() * force)

# ---- 掉落（比如持有者死亡时被释放），不产生冲量 ----
func drop() -> void:
	if current_state != State.HELD:
		return
	current_state = State.IDLE
	hitbox.set_deferred("monitoring", false)
	# 死亡可能在物理回调里触发，把"放回世界"推迟到安全时机
	_release.call_deferred()
