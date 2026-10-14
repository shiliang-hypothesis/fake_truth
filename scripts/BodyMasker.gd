class_name BodyMasker
extends Node

## 把 TagComponent 的标签翻译成"该物体属于哪个世界、和谁碰撞"。
##
## 设计原则：**规则写在这里，效果涌现出去。**
## 任何物体只要挂上正确的身份标签，就自动获得：
##   · 属于自己世界的碰撞层
##   · 只和"同一个世界"的东西碰撞（两个世界互不干扰是规则的自然结果，不是特判）
##   · 只在当前世界可见
##   · 不在当前世界时物理冻结、受击盒失效
##
## 挂载规则：和 TagComponent 平级；父节点是 CollisionObject2D。

enum World { REAL, DEATH }

## 身份标签 -> { layer, mask, world }
## layer = 我是谁；mask = 我要撞谁；world = 我属于哪个世界
##
## ★ 每个世界内部完全对称：把下面的 real_* 全部换成 dead_* 就是另一个世界。
##   这条对称性就是"两个世界互不干扰"的来源。
##
## 层号速查（project.godot）：
##   1 RealEnv  2 DeathEnv  3 RealPlayer  4 DeathPlayer
##   5 RealPlayerHurtbox  6 DeathPlayerHurtbox  7 RealSensor  8 DeathSensor
##   9 RealBody  10 DeathBody  11 RealEnemy  12 DeathEnemy  13 EnemyHurtbox
##
## mask 一律写成"层号对应的位值之和"：
##   层1=1  层2=2  层3=4  层4=8  层5=16  层6=32  层7=64  层8=128
##   层9=256  层10=512  层11=1024  层12=2048  层13=4096
const PROFILES := {
	# ---- 实类世界 ----
	# 玩家: 站本世界地面(1) + 能推本世界物品(256) + 撞本世界生物(1024)
	"real_player":  { "layer": 4,    "mask": 1281, "world": World.REAL },
	"real_hurtbox": { "layer": 16,   "mask": 0,    "world": World.REAL },  # 只被别人检测
	# 生物: 站地面(1) + 撞玩家(4) + 撞物品(256)
	"real_enemy":   { "layer": 1024, "mask": 261,  "world": World.REAL },
	# 物品: 站地面(1) + 被玩家推(4) + 撞其它物品(256) + 被生物撞(1024)
	"real_body":    { "layer": 256,  "mask": 1285, "world": World.REAL },  # 1+4+256+1024
	# 检测层: 检测本世界的角色(4) + 生物(1024)
	"real_sensor":  { "layer": 64,   "mask": 1028, "world": World.REAL },
	# 环境: 挡住本世界角色(4) + 生物(1024) + 物品(256)
	"real_tile":    { "layer": 1,    "mask": 1284, "world": World.REAL },

	# ---- 死亡世界（与上面完全对称）----
	"dead_player":  { "layer": 8,    "mask": 2562, "world": World.DEATH }, # 2+512+2048
	"dead_hurtbox": { "layer": 32,   "mask": 0,    "world": World.DEATH },
	"dead_enemy":   { "layer": 2048, "mask": 522,  "world": World.DEATH }, # 2+8+512
	"dead_body":    { "layer": 512,  "mask": 2570, "world": World.DEATH }, # 2+8+512+2048
	"dead_sensor":  { "layer": 128,  "mask": 2056, "world": World.DEATH }, # 8+2048
	"dead_tile":    { "layer": 2,    "mask": 2568, "world": World.DEATH }, # 8+512+2048

	# ---- 判定盒：不参与世界切换 ----
	# 敌人的受击盒：永远挂在 EnemyHurtbox 层，由同世界玩家的 Hitbox 检测
	"enemy_hurtbox": { "layer": 4096, "mask": 0,    "world": World.REAL },
	# 敌人的攻击盒：检测同世界玩家的受击盒（real -> real_hurtbox 层16，dead -> dead_hurtbox 层32）
	"enemy_attack":      { "layer": 0, "mask": 16,   "world": World.REAL },
	"dead_enemy_attack": { "layer": 0, "mask": 32,   "world": World.DEATH },
	# 推动感应区（玩家的 PushArea）：自己不是物品，只负责"检测同世界可推动的东西"
	"body_sensor":   { "layer": 0,    "mask": 3840, "world": World.REAL },  # 256+512+1024+2048（物品+生物）
	# 拾取感应区（玩家的 GrabArea）：只检测"物品"，不检测生物
	"item_sensor":   { "layer": 0,    "mask": 768,  "world": World.REAL },  # 256+512（real_body+dead_body）
	# 挤压感应区（玩家的 CrushArea）：检测"压在身上 / 把自己卡住"的东西。
	# 同世界的物品(real_body 256) + 环境(real_tile 1) —— 石子、尸体、墙/天花板。
	"real_crush":    { "layer": 0,    "mask": 257,  "world": World.REAL },
	"dead_crush":    { "layer": 0,    "mask": 514,  "world": World.DEATH },
}

## 优先级：一个物体同时有多个标签时，排在前面的赢
const IDENTITY_PRIORITY := [
	"dead_player", "real_player",
	"dead_enemy", "real_enemy",
	"dead_body", "real_body",
	"dead_sensor", "real_sensor",
	"dead_tile", "real_tile",
	"dead_hurtbox", "real_hurtbox",
	"enemy_hurtbox", "enemy_attack", "dead_enemy_attack", "body_sensor", "item_sensor",
	"dead_crush", "real_crush",
]

@export var tag_component_path: NodePath = ^"../TagComponent"

var _tags: TagComponent
var _body: CollisionObject2D
var _refresh_queued := false


func _ready() -> void:
	_body = get_parent() as CollisionObject2D
	if _body == null:
		push_error("BodyMasker 的父节点必须是 CollisionObject2D，当前是 %s" % get_parent())
		return

	_tags = get_node_or_null(tag_component_path) as TagComponent
	if _tags == null:
		push_error("BodyMasker 找不到 TagComponent: %s" % tag_component_path)
		return

	Game.world_changed.connect(_on_world_changed)
	_tags.tags_changed.connect(_on_tags_changed)
	_queue_refresh()


## ★ 两件事靠"推迟一帧"一次解决：
##   1) Godot 子节点先于父节点 _ready()，此刻父节点还没加标签；
##   2) 形态切换会连续 remove/add 好几个标签（real_player -> dead_player），
##      如果每次改动都立刻 refresh，会经过"一个身份标签都没有"的中间态，
##      于是刷一堆无意义警告、还要反复改碰撞。
##   合并成一次延迟执行，既避开中间态，也避开物理回调期间改碰撞体。
func _on_tags_changed() -> void:
	_queue_refresh()

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh_deferred.call_deferred()

func _refresh_deferred() -> void:
	_refresh_queued = false
	refresh()


## 找到当前生效的身份
func get_identity() -> String:
	if _tags == null:
		return ""
	for identity in IDENTITY_PRIORITY:
		if _tags.has_tag(identity):
			return identity
	return ""


## 身份变了（比如玩家死亡 real_player -> dead_player）就重新套用全部规则
func refresh() -> void:
	if _body == null:
		return

	var identity := get_identity()
	if identity == "":
		# 找不到身份标签时"什么都不做"，保留场景里手配的值。
		# 这里绝不能改成清零：那会在"忘加标签"时静默移除碰撞，
		# 表现为物体直接穿过地面掉出地图，极难排查。
		push_warning("BodyMasker: '%s' 没有任何身份标签，保留原有碰撞配置" % get_parent().name)
		return

	var p: Dictionary = PROFILES[identity]
	_body.set_deferred("collision_layer", p["layer"])
	_body.set_deferred("collision_mask", p["mask"])
	_apply_world(p["world"])


## ★ 两个世界互不干扰的规则就落在这里：
##   不属于当前世界的东西 —— 不可见、物理冻结、不再被任何东西检测到。
##   不需要给"小怪看不见灵魂态玩家"这种需求写任何专门的代码。
func _apply_world(world: int) -> void:
	var here: bool = world == Game.current_world

	# 可见性：Node2D / CanvasItem 才有
	if _body is CanvasItem:
		(_body as CanvasItem).visible = here

	# 物理冻结：只有 RigidBody2D 有 freeze 属性，而且只有它需要。
	#   Area2D / StaticBody2D 没有 freeze；
	#   CharacterBody2D 也没有 freeze（它只在有输入时移动，隐藏+撤掉碰撞层
	#   已经足够让它"不在这个世界里"了）。
	#
	# ★ 这里必须直接赋值，不能用 set_deferred：
	#   冻结的 RigidBody2D 会从碰撞检测中移除，被 set_deferred 吞掉的话
	#   尸体会一直保持冻结 —— 表现为"推不动尸体"（Area2D 根本检测不到它）。
	#   _apply_world 本身就是通过 call_deferred 执行的，已经脱离了物理回调，
	#   所以直接赋值是安全的。
	if _body is RigidBody2D:
		(_body as RigidBody2D).freeze = not here

	# 不在当前世界时不再被任何东西检测到。
	# ★ 只动 monitorable（"我能不能被别人检测到"），
	#   绝不动 monitoring（"我还能不能检测别人"）——
	#   玩家的 PushArea 正是靠自己 monitoring 去发现物品的，
	#   把它关掉会导致 get_overlapping_bodies() 直接报错。
	if _body is Area2D:
		(_body as Area2D).set_deferred("monitorable", here)


## 世界切换也走延迟刷新。
## 直接同步改 monitoring/freeze 会在物理回调期间（比如地刺的 body_entered
## 里调 die() → set_world()）触发
## "Can't change this state while flushing queries" 报错。
func _on_world_changed(_new_world: int) -> void:
	if _tags == null:
		return
	_queue_refresh()
