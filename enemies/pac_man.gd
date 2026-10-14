extends Enemy

enum State{
	IDLE,
	WALK,
	RUN,
	HURT,
	DYING,
	DEAD
}

const KNOCKBACK_AMOUNT := 512.0
const CORPSE_SCENE := preload("res://corpses/corpse_of_pacman.tscn")
const DEAD_TINT := Color(0.0, 81.0 / 255.0, 1.0, 1.0)
const ALIVE_TINT := Color.WHITE

@onready var wall_checker: RayCast2D = $Graphics/WallChecker
@onready var player_checker: RayCast2D = $Graphics/PlayerChecker
@onready var floor_checker: RayCast2D = $Graphics/FloorChecker
@onready var calm_down_timer: Timer = $CalmDownTimer


var _is_dead := false

func can_see_player() -> bool:
	if not player_checker.is_colliding():
		return false
	var other := player_checker.get_collider()
	if other == null:
		return false
	var t = other.get_node_or_null("TagComponent")
	if t == null:
		return false
	return t.has_tag("real_player")

func tick_physics(state:State, delta:float) -> void:
	match state:
		State.IDLE, State.HURT, State.DYING:
			move(0.0, delta )
		State.WALK,State.DEAD:
			move(max_speed / 3, delta)
		State.RUN:
			if wall_checker.is_colliding() or not floor_checker.is_colliding():
				if direction == Direction.LEFT:
					direction = Direction.RIGHT
				else :
					direction = Direction.LEFT
			move(max_speed, delta)
			if can_see_player():
				calm_down_timer.start()

## 当前形态的"闲置态"是哪个
func _idle_state() -> int:
	return State.DEAD if tags.has_tag("dead_enemy") else State.IDLE

func get_next_state(state:State) -> int:
	if _is_dead:
		return StateMachine.KEEP_CURRENT
	
	if stats.health == 0:
		return StateMachine.KEEP_CURRENT if state == State.DYING else   State.DYING
	
	if pending_damage:
		return State.HURT
	
	match state:
		State.DEAD:
			if state_machine.state_time > 2:
				return State.WALK
			return StateMachine.KEEP_CURRENT
		
		State.IDLE:
			if can_see_player():
				return State.RUN
			if state_machine.state_time > 2:
				return State.WALK
		
		State.WALK:
			if can_see_player():
				return State.RUN
			if wall_checker.is_colliding() or not floor_checker.is_colliding():
				return _idle_state()
		
		State.RUN:
			if not can_see_player() and calm_down_timer.is_stopped():
				return State.WALK
		
		State.HURT:
			if not animation_player.is_playing():
				return State.RUN
	
	return StateMachine.KEEP_CURRENT


func transition_state(from:State, to:State) -> void:
	match to:
		State.IDLE:
			animation_player.play("idle")
			if wall_checker.is_colliding():
				if direction == Direction.LEFT:
					direction = Direction.RIGHT
				else :
					direction = Direction.LEFT
		
		State.WALK:
			animation_player.play("walk")
			if not floor_checker.is_colliding():
				if direction == Direction.LEFT:
					direction = Direction.RIGHT
				else :
					direction = Direction.LEFT
				floor_checker.force_raycast_update()
		
		State.RUN:
			animation_player.play("run")
		
		State.HURT:
			animation_player.play("hit")
			
			stats.health -= pending_damage.amount
			
			var dir := pending_damage.source.global_position.direction_to(global_position)
			velocity = dir * KNOCKBACK_AMOUNT
			
			if dir.x > 0:
				direction = Direction.LEFT
			else:
				direction = Direction.RIGHT
			
			pending_damage = null
		
		State.DYING:
			animation_player.play("dead")
		
		State.DEAD:
			animation_player.play("idle")  
			_is_dead = false   

func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	if tags.has_tag("real_enemy"):
		_first_death()
	else:
		_true_death()

func _first_death() -> void:
	_spawn_corpse()
	_enter_dead_form()
	stats.reset()                                  
	pending_damage = null                 
	state_machine.current_state = State.DEAD 

func _true_death() -> void:
	queue_free()

func _spawn_corpse() -> void:
	var corpse := CORPSE_SCENE.instantiate()
	corpse.global_position = global_position + Vector2(0, -8)
	corpse.rotation = 0.0
	# ★ 用 call_deferred 入树：die() 可能是在物理回调里被调用的
	#   （地刺的 body_entered 就是），那时往场景树里塞刚体会触发
	#   "Can't change this state while flushing queries" 一类的物理服务器报错。
	#   尸体的碰撞层由它自己的 real_body 标签决定，不要复制玩家的层。
	get_parent().add_child.call_deferred(corpse)

func _enter_dead_form() -> void:
	# 蓝色调放到 Sprite2D 上：pac_man 的 idle/walk/run 动画会把 Graphics:modulate
	# 每帧重置回白色，只有 Sprite2D:modulate 能保留灵魂色调。
	($Graphics/Sprite2D as Sprite2D).modulate = DEAD_TINT

	tags.remove_tag("real_enemy")
	tags.remove_tag("real_alive")
	tags.add_tag("dead_enemy")

	# 受击盒保持 enemy_hurtbox（层 4096）：玩家的 Hitbox 固定检测 4096，无需换层。
	# 若换成 dead_hurtbox(层 32)，会和自己的 dead_enemy_attack(掩码 32) 互相检测，
	# 导致灵魂小怪每帧自伤、血量归零被 queue_free。
	var atk_tags: TagComponent = $Graphics/Hitbox/TagComponent
	atk_tags.remove_tag("enemy_attack")
	atk_tags.add_tag("dead_enemy_attack")

func _on_hurtbox_hurt(hitbox: Hitbox) -> void:
	apply_damage(1, hitbox.owner)
