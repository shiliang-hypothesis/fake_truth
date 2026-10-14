class_name Player
extends CharacterBody2D

enum Direction {
	LEFT = -1,
	RIGHT = +1
}

enum State {
	IDLE,
	RUNNING,
	JUMP,
	FALL,
	LANDING,
	KICK,
	ROLL,
	HURT,
	DYING,
	DEAD
}

const GROUND_STATE := [State.IDLE, State.RUNNING,State.LANDING,State.KICK] #在地面的状态
const RUN_SPEED := 160.0 #跑速
const FLOOR_ACCELERATION =RUN_SPEED / 0.2 #地面加速度
const AIR_ACCELERATION =RUN_SPEED / 0.02 #空中加速度
const JUMP_VELOCITY := -300.0 #跳跃量
const KNOCKBACK_AMOUNT := 512.0 #击飞
const CORPSE_SCENE := preload("res://corpses/corpse_of_player.tscn")
const DEAD_TINT := Color(0.0, 81.0 / 255.0, 1.0, 1.0)
const ALIVE_TINT := Color.WHITE
const PUSH_GAIN := 4.0        # 推力增益：意图速度 × 这个系数

@export var direction := Direction.RIGHT:
	set(v):
		direction = v
		if not is_node_ready():
			await ready
		graphics.scale.x = direction

var default_gravity := ProjectSettings.get("physics/2d/default_gravity") as float
var is_first_tick := false
var pending_damage: Damage
var _is_dead := false
var _fell_too_long := false   # 本次坠落是否已超过 6 秒（FallTimer 超时置位）
var _crushing_count := 0      # 挤压感应区里当前压着我的物体数量
var held_item: Node2D = null   # 手里拿着的可扔物品（null = 空手）
var interacting_with: Array[Interactable]
var interacting_of_death_with: Array[InteractableOfDeath]

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var coyote_timer: Timer = $CoyoteTimer #郊狼时间
@onready var jump_request_timer: Timer = $JumpRequestTimer #跳跃预输入
@onready var stats: Stats = Game.player_stats
@onready var graphics: Node2D = $Graphics
@onready var invincible_timer: Timer = $InvincibleTimer
@onready var state_machine: StateMachine = $StateMachine
@onready var tags: TagComponent = $TagComponent
@onready var push_area: Area2D = $Graphics/PushArea
@onready var grab_area: Area2D = $Graphics/GrabArea   # 拾取感应区
@onready var hand: Node2D = $Graphics/Hand            # 手的位置，拿东西挂这里
@onready var interaction_icon: AnimatedSprite2D = $InteractionIcon
@onready var fall_timer: Timer = $FallTimer             # 坠落计时：FALL 超 6 秒落地即死
@onready var crush_timer: Timer = $CrushTimer           # 挤压计时：被压满 3 秒即死
@onready var crush_area: Area2D = $Graphics/CrushArea   # 挤压感应区（头顶 + 躯干）

func _ready() -> void:
	tags.add_tag("real_player")
	tags.add_tag("real_alive")
	
	

	# 判定盒各自有身份标签，BodyMasker 会据此管理它们的碰撞层和世界可见性。
	# 受击盒跟着玩家形态走：灵魂态时切到 dead_hurtbox（只有灵魂世界能打到我）。
	var hb_tags: TagComponent = $Graphics/Hurtbox/TagComponent
	hb_tags.add_tag("real_hurtbox")

	# ★ 推不是"推尸体"，而是"对同世界的物品施加力"。
	#   所以这个判定区是通用身份 body_sensor（物品感应区），
	#   以后尸体、灯、箱子都在这条规则里，不需要改代码。
	(push_area.get_node("TagComponent") as TagComponent).add_tag("body_sensor")

	# 拾取感应区：只感应"物品"（item_sensor），谁有 grab() 谁就能被捡。
	(grab_area.get_node("TagComponent") as TagComponent).add_tag("item_sensor")

	# 挤压感应区：检测压在头顶 / 卡在体内的东西（石子、尸体、墙）。
	(crush_area.get_node("TagComponent") as TagComponent).add_tag("real_crush")

	push_area.body_entered.connect(_on_push_body_entered)

	crush_area.body_entered.connect(_on_crush_body_entered)
	crush_area.body_exited.connect(_on_crush_body_exited)
	fall_timer.timeout.connect(_on_fall_timeout)
	crush_timer.timeout.connect(_on_crush_timeout)


func _on_push_body_entered(body: Node2D) -> void:
	# 撞上的那一瞬间补一记，手感上"顶得动"
	apply_push(body, 1.0 / 60.0)

func _physics_process(delta: float) -> void:
	# monitoring 关闭时查询重叠会报错（世界切换的瞬间会短暂关闭）
	if not push_area.monitoring:
		return
	# 持续推：贴在物品上时每帧按当前速度施力
	for body in push_area.get_overlapping_bodies():
		apply_push(body, delta)


## ★ 通用规则：对"同世界可推动的东西"施加力，力的大小正比于施加者的意图速度。
##
## 推谁不在这里判断 —— 判定区的 BodyMasker 已经按标签决定了它能碰到谁（物品+生物）。
## 这里只做一件事：把接触到的物体按玩家想去的方向推开。
## 以后灵魂态推虚类石头、贪吃兽撞飞东西，复用同一套即可。
func apply_push(body: Node2D, delta: float) -> void:
	# ★ 推的驱动力是"意图方向"（玩家想往哪走），不是"实际速度"。
	#   撞上物体时 move_and_slide 会把 velocity.x 清零，
	#   用实际速度判断会得出"被挡着→速度为零→没推力"的错误结论。
	var movement := Input.get_axis("move_left", "move_right")
	if is_zero_approx(movement):
		return          # 站着不动就没有推力（这是设计，不是缺陷）

	# movement 自带正负号，力的方向自动正确，不需要算"谁在左边"
	var force := movement * RUN_SPEED * PUSH_GAIN * delta

	# ★ 唯一规则：谁有 push() 谁就能被推，不判断它是什么类型。
	#   刚体（尸体/箱子）在自己的 push() 里叫醒 + apply_central_impulse；
	#   生物（小怪）在自己的 push() 里用残余速度表达被顶一下。
	#   以后新增可推的东西，只要实现 push()，就自动落进这条规则。
	if body.has_method("push"):
		body.push(Vector2(force, 0.0))


## 拾取：从感应区里找一个"有 grab() 能力"的物品拿起来。
## 捡谁不在这里判断 —— 感应区按 item_sensor 标签只碰到物品，
## 这里只看它有没有 grab() 这个能力。和 push 同一套"方法即能力"的规则。
func _try_grab() -> void:
	if not grab_area.monitoring:
		return
	for body in grab_area.get_overlapping_bodies():
		if body.has_method("grab"):
			held_item = body
			body.grab(self, hand)
			return

func _throw_held_item() -> void:
	if held_item == null:
		return
	var dir := Vector2(graphics.scale.x, 0.0)   # 朝面朝的方向扔
	held_item.throw(dir)
	held_item = null

## 掉落：死亡等场景下，把手里东西放回世界（不产生冲量）
func _drop_held_item() -> void:
	if held_item == null:
		return
	held_item.drop()
	held_item = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		jump_request_timer.start()
	if event.is_action_released("jump") and velocity.y < JUMP_VELOCITY / 3:
		velocity.y = JUMP_VELOCITY / 3 
	if event.is_action_pressed("restart"):
		revive_at()   # 原地复活；以后接复活点时改成 revive_at(复活点位置)
	if event.is_action_pressed("grab"):
		if held_item:
			_throw_held_item()
		else:
			_try_grab()
	if event.is_action_pressed("interact") and interacting_with:
		interacting_with.back().interact()
	if event.is_action_pressed("interact") and interacting_of_death_with:
		interacting_of_death_with.back().interact()

func tick_physics(state:State, delta: float) -> void: #每帧做的事
	interaction_icon.visible = not interacting_with.is_empty() or not interacting_of_death_with.is_empty()
	
	if invincible_timer.time_left > 0:
		graphics.modulate.a = sin(Time.get_ticks_msec() / 20.0) * 0.5 + 0.5
	else:
		graphics.modulate.a = 1
	
	match state:
		State.IDLE:
			move(default_gravity, delta)
		
		State.RUNNING:
			move(default_gravity, delta)
		
		State.JUMP:
			move(0.0 if is_first_tick else default_gravity, delta)
		
		State.FALL:
			move(default_gravity, delta)
		
		State.LANDING:
			stand(delta)
		
		State.KICK:
			move(default_gravity, delta)
		
		State.HURT, State.DYING:
			stand(delta)
		
		State.DEAD:
			move(default_gravity / 2.0, delta)
	
	
	is_first_tick = false
	


func move(gravity:float,delta: float) ->void:	 #移动
	var movement := Input.get_axis("move_left","move_right")
	var acceleration = FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x,movement * RUN_SPEED,acceleration * delta) #有加速度的移动有
	velocity.y +=gravity * delta	
	
	if not is_zero_approx(movement):
		direction = Direction.LEFT if movement <  0 else Direction.RIGHT
	
	move_and_slide()


func stand(delta:float) -> void:
	var acceleration = FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x,0.0,acceleration * delta) #有加速度的移动
	velocity.y +=default_gravity * delta	
	
	move_and_slide()

func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	if tags.has_tag("real_player"):
		_first_death()      
	else:
		_true_death()

func _first_death() -> void:
	_drop_held_item()   # 死的时候手里东西先掉回世界，不跟着进灵魂
	_spawn_corpse()
	_enter_dead_form()
	stats.reset()
	pending_damage = null
	fall_timer.stop()
	crush_timer.stop()
	_crushing_count = 0
	invincible_timer.start()
	state_machine.current_state = State.DEAD

func _true_death() -> void:
	Game.reset()
	get_tree().reload_current_scene()

func _spawn_corpse() -> void:
	var corpse := CORPSE_SCENE.instantiate()
	# 玩家的原点在脚底，尸体的碰撞盒底边在 origin + 8，所以尸体要往上放 8px 才能躺在地面上
	corpse.global_position = global_position + Vector2(0, -8)
	corpse.rotation = 0.0
	# ★ 用 call_deferred 入树：die() 可能是在物理回调里被调用的
	#   （地刺的 body_entered 就是），那时往场景树里塞刚体会触发
	#   "Can't change this state while flushing queries" 一类的物理服务器报错。
	#   尸体的碰撞层由它自己的 real_body 标签决定，不要复制玩家的层。
	get_parent().add_child.call_deferred(corpse)

func _enter_dead_form() -> void:
	var t := graphics.modulate
	graphics.modulate = Color(DEAD_TINT.r, DEAD_TINT.g, DEAD_TINT.b, t.a)

	# 换身份。BodyMasker 监听到 tags_changed 会自动完成全部后续：
	#   碰撞层 RealPlayer -> DeathPlayer
	#   在当前世界（死亡世界）可见
	# 受击盒也要跟着换世界，否则灵魂世界里的玩家会被实体世界的怪打到
	tags.remove_tag("real_player")
	tags.remove_tag("real_alive")
	tags.add_tag("dead_player")

	var hb_tags: TagComponent = $Graphics/Hurtbox/TagComponent
	hb_tags.remove_tag("real_hurtbox")
	hb_tags.add_tag("dead_hurtbox")

	var crush_tags: TagComponent = $Graphics/CrushArea/TagComponent
	crush_tags.remove_tag("real_crush")
	crush_tags.add_tag("dead_crush")

	Game.set_world(Game.World.VIRTUAL)

## 当前形态的"闲置态"是哪个
func _idle_state() -> int:
	return State.DEAD if tags.has_tag("dead_player") else State.IDLE

func get_next_state(state: State) -> int: #输入改变
	if _is_dead:
		return StateMachine.KEEP_CURRENT
	
	if stats.health == 0:
		return StateMachine.KEEP_CURRENT if state == State.DYING else   State.DYING
	
	if pending_damage:
		return State.HURT
	
	var can_jump := is_on_floor() or coyote_timer.time_left > 0 
	var should_jump := can_jump and jump_request_timer.time_left > 0
	if should_jump:
		return State.JUMP
	
	if state in GROUND_STATE and not is_on_floor():
		return State.FALL
	
	var movement := Input.get_axis("move_left","move_right")
	var is_still := is_zero_approx(movement) and is_zero_approx(velocity.x)
	match state:
		State.DEAD:
			if not is_still:
				return State.RUNNING
			return StateMachine.KEEP_CURRENT
		
		State.IDLE:
			if Input.is_action_just_pressed("kick"):
				return State.KICK
			if not is_still:
				return State.RUNNING
		
		State.RUNNING:
			if Input.is_action_just_pressed("kick"):
				return State.KICK
			if is_still:
				return _idle_state()
		
		State.JUMP:
			if velocity.y >=0:
				return State.FALL
		
		State.FALL:
			if is_on_floor():
				return State.LANDING
		
		State.LANDING:
			if not animation_player.is_playing():
				return _idle_state()
		
		State.KICK:
			if not animation_player.is_playing():
				return _idle_state()
		
		State.ROLL:
			pass
		
		State.HURT:
			if not animation_player.is_playing():
				return _idle_state()
		
		State.DYING:
			pass
		
	return StateMachine.KEEP_CURRENT


func transition_state(from:State, to:State) -> void: #状态改变：from，to
	
	if from not in GROUND_STATE and to in GROUND_STATE:
		coyote_timer.stop()
	
	match to:
		State.IDLE:
			animation_player.play("idle")
		
		State.RUNNING:
			animation_player.play("running")
		
		State.JUMP:
			animation_player.play("jump")
			velocity.y = JUMP_VELOCITY
			coyote_timer.stop()
			jump_request_timer.stop()
		
		State.FALL:
			animation_player.play("fall")
			_fell_too_long = false
			fall_timer.start()   # 从这一刻开始算"坠落了多久"
			if from in GROUND_STATE:
				coyote_timer.start()
		
		State.LANDING:
			animation_player.play("landing")
			fall_timer.stop()
			if _fell_too_long:
				apply_damage(stats.max_health, self)   # 摔落超过 6 秒：落地即秒杀
			
		State.KICK:
			animation_player.play("kick1")
		
		State.HURT:
			animation_player.play("hit")
			
			stats.health -= pending_damage.amount
			
			var dir := pending_damage.source.global_position.direction_to(global_position)
			velocity = dir * KNOCKBACK_AMOUNT
			
			pending_damage = null
			invincible_timer.start()
		
		State.DYING:
			animation_player.play("dead")
			invincible_timer.stop()
			interacting_with.clear()
		
		State.DEAD:
			animation_player.play("idle")  
			_is_dead = false                
			invincible_timer.stop()
	
	is_first_tick = true


## 统一的受伤入口：小怪 hitbox、地刺都走这里。
## 只记录 pending_damage，真正的扣血、击飞、死亡动画由状态机在 HURT/DYING 里处理。
func apply_damage(amount: int, source: Node2D) -> void:
	if invincible_timer.time_left > 0:
		return
	pending_damage = Damage.new()
	pending_damage.amount = amount
	pending_damage.source = source


func _on_hurtbox_hurt(hitbox: Hitbox) -> void:
	apply_damage(1, hitbox.owner)


# ---- 坠落 / 挤压：两种"环境致死"，都和地刺一样走 apply_damage(max_health) 秒杀通道 ----

## 挤压：感应区里一有东西压着（石子/尸体/墙），计时器就开始走；东西一离开就清零。
## 连续压满 3 秒 -> _on_crush_timeout -> 秒杀。
func _on_crush_body_entered(_body: Node2D) -> void:
	_crushing_count += 1
	if not _is_dead and crush_timer.is_stopped():
		crush_timer.start()

func _on_crush_body_exited(_body: Node2D) -> void:
	_crushing_count = maxi(_crushing_count - 1, 0)
	if _crushing_count == 0:
		crush_timer.stop()

func _on_crush_timeout() -> void:
	if _is_dead:
		return
	apply_damage(stats.max_health, self)

## 坠落：进入 FALL 时启动 6 秒 FallTimer，超时置位 _fell_too_long；
## LANDING 时若已超时，由 transition_state 落地即秒杀。
func _on_fall_timeout() -> void:
	_fell_too_long = true


#复活函数
func revive_at(pos: Vector2 = global_position) -> void:
	# 1) 只有死亡形态才需要复活
	if not tags.has_tag("dead_player"):
		return

	# 2) 换身份标签（BodyMasker 自动把层切回 RealPlayer 并恢复可见）
	tags.remove_tag("dead_player")
	tags.add_tag("real_player")
	tags.add_tag("real_alive")           # ★ 重新变回"活着的现实生物"

	var hb_tags: TagComponent = $Graphics/Hurtbox/TagComponent
	hb_tags.remove_tag("dead_hurtbox")
	hb_tags.add_tag("real_hurtbox")

	var crush_tags: TagComponent = $Graphics/CrushArea/TagComponent
	crush_tags.remove_tag("dead_crush")
	crush_tags.add_tag("real_crush")

	# 3) 恢复视觉
	var t := graphics.modulate
	graphics.modulate = Color(ALIVE_TINT.r, ALIVE_TINT.g, ALIVE_TINT.b, t.a)

	# 4) 血量补满
	stats.reset()

	# 5) 位置和速度
	global_position = pos
	velocity = Vector2.ZERO

	# 6) 清掉残留状态
	pending_damage = null
	_fell_too_long = false
	_crushing_count = 0
	invincible_timer.start()             # 复活后给一段无敌

	# 7) 回实类世界
	Game.set_world(Game.World.REAL)

	# 8) 解除锁 + 强制切闲置态
	#    注意顺序：_is_dead 必须先清，否则 current_state 的赋值会被 get_next_state 的锁挡住
	_is_dead = false
	state_machine.current_state = State.IDLE

func register_interactable(v: Interactable) -> void:
	if state_machine.current_state == State.DYING:
		return
	if v in interacting_with:
		return
	interacting_with.append(v)

func unregister_interactable(v: Interactable) -> void:
	interacting_with.erase(v)

func register_interactable_of_death(v: InteractableOfDeath) -> void:
	if state_machine.current_state == State.DYING:
		return
	if v in interacting_of_death_with:
		return
	interacting_of_death_with.append(v)

func unregister_interactable_of_death(v: InteractableOfDeath) -> void:
	interacting_of_death_with.erase(v)
