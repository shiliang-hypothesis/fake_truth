class_name Enemy
extends CharacterBody2D

enum Direction {
	RIGHT = +1,
	LEFT = -1
}

@export var direction := Direction.RIGHT:
	set(v):
		direction = v
		if not is_node_ready():
			await ready
		graphics.scale.x = -direction
@export var max_speed: float = 180
@export var acceleration: float = 2000

var default_gravity := ProjectSettings.get("physics/2d/default_gravity") as float

var pending_damage: Damage
var _push_speed := 0.0   # 被推的残余速度（生物没有刚体惯性，用它表达"被顶了一下"）

@onready var graphics: Node2D = $Graphics
@onready var state_machine: StateMachine = $StateMachine
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var stats: Stats = $Stats
@onready var tags: TagComponent = $TagComponent


## 身份标签是唯一事实来源：BodyMasker 会据此自动设置碰撞层、
## 决定它属于哪个世界、以及不在当前世界时是否可见/冻结。
func _ready() -> void:
	tags.add_tag("real_enemy")
	tags.add_tag("real_alive")   # 地刺靠它把敌人也算作"活着的现实生物"

	# 受击盒声明身份，不需要在这里碰任何碰撞层数字
	var eb_tags: TagComponent = $Graphics/Hurtbox/TagComponent
	eb_tags.add_tag("enemy_hurtbox")

	# 攻击盒声明身份：检测同世界玩家的受击盒（死后由子类切到 dead_enemy_attack）
	var atk_tags: TagComponent = $Graphics/Hitbox/TagComponent
	atk_tags.add_tag("enemy_attack")



func move(speed: float, delta: float) -> void:
	velocity.x = move_toward(velocity.x,direction * speed,acceleration * delta) #有加速度的移动有
	velocity.y +=default_gravity * delta	
	
	# 被推的残余速度叠在 AI 速度之上，并逐帧衰减：贴着持续推才顶得动，离开推力源就慢慢停。
	velocity.x += _push_speed
	_push_speed *= 0.8

	move_and_slide()



## 被推：把外部水平冲量折算成残余速度。CharacterBody2D 没有刚体惯性，
## 所以这里用一个会衰减的量，让"顶一下"有手感，又不会和 AI 自己的速度打架。
func push(impulse: Vector2) -> void:
	_push_speed += impulse.x


## 统一的受伤入口：和玩家一致，只记录 pending_damage，
## 真正的扣血、击飞、死亡动画由子类状态机在 HURT/DYING 里处理。
func apply_damage(amount: int, source: Node2D) -> void:
	pending_damage = Damage.new()
	pending_damage.amount = amount
	pending_damage.source = source
