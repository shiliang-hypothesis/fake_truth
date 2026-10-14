# 世界规则与物理层方案

> 这份文档记录 fake-truth 的"规则驱动"架构。核心原则：
> **规则写一遍，效果自己涌现；不给具体需求写特判。**

---

## 一、物理层划分（project.godot）

| 层 | 名称 | 装什么 |
|---|---|---|
| 1 | RealEnvironment | 实类世界地形 |
| 2 | DeathEnvironment | 死亡世界地形 |
| 3 | RealPlayer | 实类形态玩家 |
| 4 | DeathPlayer | 死亡形态玩家 |
| 5 | RealPlayerHurtbox | 实类玩家受击盒 |
| 6 | DeathPlayerHurtbox | 死亡形态玩家受击盒 |
| 7 | RealSensor | 实类检测器（地刺、压力板…） |
| 8 | DeathSensor | 死亡世界检测器 |
| 9 | RealBody | 实类物品（尸体、以后的灯、箱子…） |
| 10 | DeathBody | 死亡世界物品 |
| 11 | RealEnemy | 实类生物 |
| 12 | DeathEnemy | 死亡世界生物 |
| 13 | EnemyHurtbox | 生物受击盒 |

**位值速查**（写 mask 时用）：
```
层1=1    层2=2     层3=4     层4=8     层5=16   层6=32
层7=64   层8=128   层9=256   层10=512  层11=1024  层12=2048  层13=4096
```

---

## 二、碰撞矩阵（BodyMasker.PROFILES）

mask 的构成规则，**每个世界完全对称**：

```
本世界环境 + 本世界角色 + 本世界物品 (+ 本世界生物)
```

| 身份标签 | layer | mask | 位分解 |
|---|---|---|---|
| real_player | 4 | 1281 | 1+256+1024 |
| real_hurtbox | 16 | 0 | 只被别人检测 |
| real_enemy | 1024 | 261 | 1+4+256 |
| real_body | 256 | 1285 | 1+4+256+1024 |
| real_sensor | 64 | 1028 | 4+1024 |
| real_tile | 1 | 1284 | 4+256+1024 |
| dead_player | 8 | 2562 | 2+512+2048 |
| dead_hurtbox | 32 | 0 | |
| dead_enemy | 2048 | 522 | 2+8+512 |
| dead_body | 512 | 2570 | 2+8+512+2048 |
| dead_sensor | 128 | 2056 | 8+2048 |
| dead_tile | 2 | 2568 | 8+512+2048 |
| enemy_hurtbox | 4096 | 0 | |
| body_sensor | 0 | 3840 | 256+512+1024+2048 |
| item_sensor | 0 | 768 | 256+512 |

> `hitbox`（攻击判定盒）不在这张表里：它是纯检测器，掩码在场景里手配
> （玩家 Hitbox `mask=4096` 检测 enemy_hurtbox；敌怪 Hitbox `mask=16` 检测 real_hurtbox；
> 石子 Hitbox `mask=4112` = 16+4096，检测 real_hurtbox + enemy_hurtbox），
> 不再交给 BodyMasker 管理，避免被 profile 的 `mask=0` 清零。

---

## 三、两个世界互不干扰是怎么来的

**不是给每个需求写特判，而是三条规则的自然结果：**

1. **碰撞层隔离** —— mask 里只列本世界的东西，所以跨世界物理上碰不到
2. **可见性** —— `BodyMasker._apply_world()` 里，不属于当前世界的物体 `visible = false`
3. **冻结** —— 不属于当前世界的 `RigidBody2D` / `CharacterBody2D` 被冻结，且 `monitorable = false`

结果（全部实测通过）：
- 死亡世界看不到实类小怪 ✓
- 死亡世界看不到实类尸体 ✓
- 实类尸体在死亡世界被冻结 ✓
- 实类小怪看不见死亡形态玩家 ✓
- 实类小怪打不到死亡形态玩家 ✓
- 灵魂世界踩不到实类地刺 ✓

**所以你不需要为"灵魂态不应该被实体小怪伤害"写任何代码** —— 换上 `dead_hurtbox` 标签，它就自动不在了。

---

## 四、地刺规则（涌现式写法）

```gdscript
# spike.gd —— 只表达一条规则，不区分玩家还是小怪
func _on_body_entered(body: Node2D) -> void:
	var t = body.get_node_or_null("TagComponent")
	if t == null or not t.has_tag("real_alive"):
		return
	var stats := body.get_node_or_null("Stats")
	if stats == null:
		return
	if body.has_method("apply_damage"):
		body.apply_damage(stats.max_health, self)
```

- 谁有 `real_alive` 标签谁就被刺 → **加新生物不用改地刺**
- 尸体也在 mask 里（层9），但尸体没有 `real_alive` → 自动免疫
- 地刺和 hitbox 走**同一条受伤通道**（`apply_damage` 只记 `pending_damage`），
  扣血 / 受伤 / 死亡动画由对方状态机在 HURT / DYING 里播放。
  伤害 = 目标最大生命值，等效秒杀，但**"先播死亡动画、再变灵魂态"的顺序被保留**。

---

## 五、推力规则（通用，不是"推尸体"）

```gdscript
# player.gd —— 对"同世界可推动的东西"施加力，力正比于意图方向（不是实际速度）
func apply_push(body: Node2D, delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	if is_zero_approx(direction):
		return          # 站着不动就没有推力（这是设计，不是缺陷）
	var force := direction * RUN_SPEED * PUSH_GAIN * delta

	# 唯一规则：谁有 push() 谁就能被推，不判断它是什么类型
	if body.has_method("push"):
		body.push(Vector2(force, 0.0))
```

```gdscript
# corpse.gd —— 刚体物品的"被推"能力：叫醒沉睡刚体 + 施加冲量
func push(impulse: Vector2) -> void:
	if sleeping:
		sleeping = false      # 沉睡的刚体会忽略小冲量，先叫醒
	apply_central_impulse(impulse)
```

```gdscript
# enemy.gd —— 生物的"被推"能力：没有刚体惯性，用残余速度表达被顶一下
func push(impulse: Vector2) -> void:
	_push_speed += impulse.x
```

- 判定区挂 `body_sensor` 标签，`BodyMasker` 给它 mask 3840（层9+10+11+12，物品+生物）
- 推谁不在这里判断 —— 判定区已经按标签决定了它能碰到谁；这里只按玩家想去的方向施力
- **关键：`apply_push` 用 `Input.get_axis`（意图方向），不是 `velocity.x`** ——
  撞上物体时 `move_and_slide` 会把 `velocity.x` 清零，用实际速度会得出"被挡着→没推力"的错误结论
- **"可推"是一个方法 `push()`，不是一个类型判断** —— 刚体/生物各自实现，`apply_push` 只问"有没有 push()"
- **低摩擦是"可推"的一部分**：`corpse.gd` 的 `_ready()` 里把 `physics_material_override.friction` 设为 0 ——
  默认摩擦 1.0 会吃掉那点小冲量，表现为"贴上去推不动"；降到 0 后靠 `linear_damp` 滑一段再停

---

## 六、拾取与投掷规则（石子）

石子 = 实类物品（`real_body`），比尸体多三种能力，同样**每种能力都是一个方法**：

```gdscript
# Rock.gd —— 能力是方法，不是类型特判
func push(impulse: Vector2) -> void: ...        # 可被推（和尸体一样）
func grab(holder: Node2D, hand: Node2D) -> void: ...  # 可被捡
func throw(direction: Vector2, force := 400.0) -> void: ...  # 可被扔
func drop() -> void: ...                        # 掉落（死亡时释放）
```

```gdscript
# player.gd —— 按 J：空手就捡，手里有东西就扔
if event.is_action_pressed("grab"):
	if held_item:
		_throw_held_item()
	else:
		_try_grab()

func _try_grab() -> void:
	for body in grab_area.get_overlapping_bodies():
		if body.has_method("grab"):   # 谁有 grab() 谁就能被捡
			held_item = body
			body.grab(self, hand)
			return
```

- **捡谁由感应区决定，不由代码判断**：`GrabArea` 挂 `item_sensor` 标签，`BodyMasker` 给它 mask 768（层9+10，只碰物品不碰生物）
- **扔出的石子能砸伤生物**：扔出瞬间 `throw()` 把 hitbox `monitoring = true`（上膛），砸到 real_hurtbox / enemy_hurtbox 走同一条 `apply_damage` 通道，各掉 1 血
- **砸到即停**：石子 `linear_damp=1` + `friction=0`，撞上东西后滑一小段；沉睡时 `sleeping_state_changed` 自动退膛（IDLE），不再伤人
- **手里时不参与碰撞**：`grab()` 里 `collision_layer/mask = 0`，避免把持有者撞开
- **被世界冻结的东西捡不了**：`grab()` 检查 `freeze` —— 不在当前世界的物品自动免疫，不是特判
- 键位：`grab`=J（原来是 kick），`kick` 改到 X

---

## 七、踩过的坑（别再犯）

| 坑 | 症状 | 正确做法 |
|---|---|---|
| `BodyMasker` 在 `_ready()` 里同步 refresh | 父节点标签还没加 → 找不到身份 → 碰撞被清零 → **掉出地图** | 用 `call_deferred()` 推迟；找不到标签时**什么都不做**并警告 |
| `Area2D as PhysicsBody2D` | 得到 null → `set_deferred` 报错 | Area2D **不是** PhysicsBody2D |
| `CharacterBody2D.freeze` | 报错：属性不存在 | 只有 `RigidBody2D` 有 freeze |
| `set_deferred("freeze", …)` | 物理回调期间被静默丢弃 → 尸体永远冻结 → **推不动** | 直接赋值（`_apply_world` 已经是 deferred 的） |
| 刚体默认摩擦 1.0 | 小冲量被地面摩擦吃掉 → 角色贴上去**推不动**尸体 | 可推物品的脚本里（`corpse.gd`）设 `physics_material_override.friction = 0`，靠 `linear_damp` 停住 |
| 物理回调里 `add_child` 刚体 | "Can't change this state while flushing queries" | `add_child.call_deferred()` |
| 连续 remove/add 标签 | 中间态无身份 → 刷警告 + 反复改碰撞 | 刷新合并成一次延迟执行 |
| 动 `Area2D.monitoring` | `get_overlapping_bodies()` 报错 | 只动 `monitorable` |
| mask 手算位值 | 少算一层 → 玩家没有地面碰撞 → 掉出地图 | 按第五节位值表逐项相加 |

---

## 八、待办

1. ✅ ~~`world.tscn` 里预置的 corpse 位置不对~~ → 已改到 y=160（地面，不再从半空掉落）
2. ✅ ~~尸体复活的瞬间与玩家重叠时会有一次物理弹开~~ → 重叠分离量实测 ~0.015px，可忽略；
   尸体 `friction=0` + `linear_damp=4` 让它被顶开后滑一小段就停，不再有生硬弹开
3. ✅ ~~`world.tscn` 里 PacMan 的 `collision_mask = 13` 旧值残留~~ → 已删除，PacMan 现用 `enemy.tscn` 的 261
