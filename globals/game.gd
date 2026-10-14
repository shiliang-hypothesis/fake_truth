extends Node

@onready var player_stats: Stats = $PlayerStats
@onready var color_rect: ColorRect = $ColorRect


func _ready() -> void:
	color_rect.color.a = 0

func change_scene(path: String, entry_point: String) -> void:
	var tree := get_tree()
	tree.paused = true
	
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(color_rect, "color:a", 1, 0.2)
	await tween.finished
	
	tree.change_scene_to_file(path)
	await tree.tree_changed
	
	for node in tree.get_nodes_in_group("entry_points"):
		if node.name == entry_point:
			tree.current_scene.update_player(node.global_position, node.direction)
			break
	
	tree.paused = false
	
	tween = create_tween()
	tween.tween_property(color_rect, "color:a", 0, 0.2)

enum World { REAL, VIRTUAL }
var current_world: World = World.REAL
# 复活点：由 World 在开局记录主角初始位置。R 键复活时回到这里。
var spawn_position: Vector2 = Vector2.ZERO

signal world_changed(new_world: World)

func set_world(world: World) -> void:
	if current_world == world:
		return
	current_world = world
	world_changed.emit(world)

func reset() -> void:
	# 走 set_world 才能发出 world_changed，否则重置后
	# 所有 BodyMasker 还以为自己在旧世界里（可见性和冻结状态不会恢复）
	set_world(World.REAL)
