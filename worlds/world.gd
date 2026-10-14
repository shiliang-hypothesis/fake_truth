# World.gd
extends Node2D

## World 只负责"当前是哪个世界"的展示层：两张地图哪张可见、摄像机的活动范围。
## 具体某个物体属于哪个世界、能不能碰撞、能不能被看见，
## 全部由该物体自己的标签 + BodyMasker 决定 —— World 不需要知道场上有谁。
## 所以这里既不用遍历敌人，也不用管尸体，加新物体永远不用回来改这个文件。

@onready var real_tilemap: TileMapLayer = $RealTileMap
@onready var virtual_tilemap: TileMapLayer = $VirtualTileMap
@onready var camera_2d: Camera2D = $Player/Camera2D
@onready var player: CharacterBody2D = $Player

func _ready() -> void:
	# 声明"本场景可以被 ESC 暂停"。PauseMenu（autoload）只对带这个组的
	# 场景响应 ESC，所以开始菜单里按 ESC 不会弹出暂停菜单。
	add_to_group("pausable_scene")

	# 复活点 = 主角出生位置。子节点先于父节点 _ready，这里读到的就是最终出生坐标。
	Game.spawn_position = player.global_position

	# 摄像机范围取两张地图的并集
	var used := real_tilemap.get_used_rect().merge(virtual_tilemap.get_used_rect())
	var tile_size := real_tilemap.tile_set.tile_size

	camera_2d.limit_left = used.position.x * tile_size.x
	camera_2d.limit_top = used.position.y * tile_size.y
	camera_2d.limit_right = used.end.x * tile_size.x
	camera_2d.limit_bottom = used.end.y * tile_size.y
	camera_2d.reset_smoothing()

	Game.world_changed.connect(_on_world_changed)
	_on_world_changed(Game.current_world)

func _on_world_changed(world: int) -> void:
	var is_real := world == Game.World.REAL
	real_tilemap.visible = is_real
	virtual_tilemap.visible = not is_real
	# 碰撞不用管：环境地图的 mask 只含自己世界的层，
	# 所以另一世界的东西本来就撞不到它。

func update_player(pos: Vector2, direction: Player.Direction) -> void:
	player.global_position = pos
	player.direction = direction
	camera_2d.reset_smoothing()
	camera_2d.force_update_scroll()
