extends Control

## 开始菜单。
##
## ★ 像素风文字由项目设置 gui/fonts/dynamic_fonts/use_oversampling=false 提供
##   （见 project.godot）。这里不再自己动 Viewport.oversampling_override ——
##   那个属性是全局的，多个场景各自保存/还原会互相打架。
##
## 本项目用 canvas_items 拉伸：384x216 画布 → 1152x648 窗口，正好 3 倍，
## 所以画布坐标就是设计坐标，字号按 384x216 的尺度给。

const GAME_SCENE := "res://worlds/test.tscn"

const CANVAS_W := 384.0
const CANVAS_H := 216.0

const DUST_COUNT := 56
## 尘埃用"纯函数"算位置（种子 + 时间），不保存每帧状态，无累积误差
const DUST_SEED := 20260607

const COLOR_BG := Color("071417")
const COLOR_DUST := Color(0.36, 0.74, 0.72, 0.42)

@onready var start_button: Button = $StartButton
@onready var quit_button: Button = $QuitButton

var _dust_x := PackedFloat32Array()
var _dust_y := PackedFloat32Array()
var _dust_speed := PackedFloat32Array()
var _dust_bright := PackedFloat32Array()

var _time := 0.0


func _ready() -> void:
	_build_dust()

	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# 上下键在两项之间循环（默认的几何自动寻径在只有两项时不会绕回）
	start_button.focus_neighbor_top = start_button.get_path_to(quit_button)
	start_button.focus_neighbor_bottom = start_button.get_path_to(quit_button)
	start_button.focus_next = start_button.get_path_to(quit_button)
	quit_button.focus_neighbor_top = quit_button.get_path_to(start_button)
	quit_button.focus_neighbor_bottom = quit_button.get_path_to(start_button)
	quit_button.focus_next = quit_button.get_path_to(start_button)

	start_button.grab_focus()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# ESC 不直接退出游戏（避免误触丢进度），只把焦点搬到"退出游戏"
	if event.is_action_pressed("ui_cancel"):
		quit_button.grab_focus()
		accept_event()


func _build_dust() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DUST_SEED
	for i in DUST_COUNT:
		_dust_x.append(rng.randf_range(2.0, CANVAS_W - 2.0))
		_dust_y.append(rng.randf_range(0.0, CANVAS_H))
		_dust_speed.append(rng.randf_range(2.0, 9.0))
		_dust_bright.append(rng.randf_range(0.25, 1.0))


func _draw() -> void:
	# 背景 + 缓慢上浮的像素尘埃。都取整到画布像素，放大后是干净的方块。
	# 选中指示三角由 PixelButton 自己画，这里不用管。
	draw_rect(Rect2(0.0, 0.0, CANVAS_W, CANVAS_H), COLOR_BG)
	for i in _dust_x.size():
		var y := fposmod(_dust_y[i] - _time * _dust_speed[i], CANVAS_H + 6.0) - 3.0
		var x := _dust_x[i] + sin(_time * 0.6 + float(i) * 1.7) * 1.5
		var c := COLOR_DUST
		c.a *= _dust_bright[i]
		draw_rect(Rect2(floorf(x), floorf(y), 1.0, 1.0), c)


func _on_start_pressed() -> void:
	# 复用 Game 现成的淡入淡出转场。
	# entry_point 传空串 = 不跳转入口点，沿用场景里布置好的出生位置。
	Game.reset()
	Game.player_stats.reset()
	Game.change_scene(GAME_SCENE, "")


func _on_quit_pressed() -> void:
	get_tree().quit()
