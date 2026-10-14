# spike.gd
extends Area2D

## 地刺只是一条规则：**对同世界里"活着的东西"造成死亡。**
## 它不区分玩家还是小怪 —— 谁满足条件就作用在谁身上。
## 以后加新的现实生物，只要打上 real_alive 标签，地刺自动对它生效，不用改这里。
##
## 跨世界隔离由 BodyMasker + 碰撞层完成：
## 实体世界的地刺属于 RealSensor 层，mask 只含同世界的角色/生物/物品，
## 所以灵魂世界的任何东西都不可能触发它 —— 这不是特判出来的，是规则的结果。

@onready var tags: TagComponent = $TagComponent

func _ready() -> void:
	tags.add_tag("real_sensor")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	var t = body.get_node_or_null("TagComponent")
	if t == null:
		return
	if not t.has_tag("real_alive"):
		return

	# 地刺和 hitbox 走同一条受伤通道：apply_damage 只记录 pending_damage，
	# 扣血、受伤/死亡动画由对方自己的状态机在 HURT/DYING 里播放。
	# 伤害 = 目标最大生命值，等效秒杀 —— 但"先播死亡动画、再变灵魂态"的顺序被保留。
	# 玩家的 Stats 挂在 Game 全局节点下（跨场景保留血量），小怪的 Stats 是自己的子节点。
	# 注意：`== Player` 是拿实例和类比较、永远为 false，判类型要用 `is Player`。
	var stats: Stats = Game.player_stats if body is Player else body.get_node_or_null("Stats") as Stats
	if stats == null:
		return
	if body.has_method("apply_damage"):
		body.apply_damage(stats.max_health, self)
