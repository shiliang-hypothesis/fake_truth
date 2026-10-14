extends Control

## ESC 暂停菜单。注册为 autoload（见 project.godot），整个游戏只需一份。
##
## 为什么做成 autoload 而不是挂进关卡：
##   "能暂停"是任何玩法场景都需要的横切能力，挂进每个关卡就要每个关卡复制一份，
##   以后新增地图漏一个就少一个功能。
##
## 为什么用 group 判断"这个场景能不能暂停"：
##   开始菜单里按 ESC 应该是"聚焦退出按钮"（main_menu.gd 自己处理），
##   不该弹出暂停菜单。让可暂停的场景自己声明身份（world.gd 里 add_to_group），
##   比在暂停菜单里硬编码某个场景路径更不容易随重构失效。
##
## 为什么绘制代码在这个 Control 上而不是 CanvasLayer 上：
##   CanvasLayer 不是 CanvasItem，画不了东西；而且它必须是场景根，
##   才能保证暂停菜单画在游戏画面之上（autoload 比主场景先入树，
##   普通 Control 会被后入树的游戏场景盖住）。

const PAUSABLE_GROUP := "pausable_scene"
const MENU_SCENE := "res://ui/main_menu.tscn"

const CANVAS_W := 384.0
const CANVAS_H := 216.0

## 面板矩形（画布坐标，384x216 设计尺度）。
## 四个按钮 + 标题 + 提示在 216 高度里比较紧，所以纵向间距按 22px 按钮 + 3px 间隔排。
const PANEL := Rect2(104.0, 26.0, 176.0, 170.0)

const COLOR_DIM := Color(0.0, 0.0, 0.0, 0.6)
const COLOR_PANEL_FILL := Color(0.031, 0.086, 0.098, 0.97)
const COLOR_PANEL_EDGE := Color("7fe8e4")
const COLOR_BEVEL_LIGHT := Color(0.247, 0.561, 0.549, 1.0)
const COLOR_BEVEL_DARK := Color("04100f")

@onready var resume_button: Button = $ResumeButton
@onready var restart_button: Button = $RestartButton
@onready var menu_button: Button = $MenuButton
@onready var quit_button: Button = $QuitButton

## 顺序即键盘上下的顺序。集中放一份，close() 释放焦点时也用它，
## 避免以后加按钮出现"接好了键盘但忘了释放焦点"。
var _buttons: Array[Button] = []

var _is_open := false


func _ready() -> void:
	visible = false
	_buttons = [resume_button, restart_button, menu_button, quit_button]

	resume_button.pressed.connect(close)
	restart_button.pressed.connect(_on_restart)
	menu_button.pressed.connect(_on_back_to_menu)
	quit_button.pressed.connect(_on_quit)

	# 上下循环（默认的几何自动寻径在首尾不会绕回）
	var count := _buttons.size()
	for i in count:
		var prev: Button = _buttons[(i - 1 + count) % count]
		var next: Button = _buttons[(i + 1) % count]
		_buttons[i].focus_neighbor_top = _buttons[i].get_path_to(prev)
		_buttons[i].focus_neighbor_bottom = _buttons[i].get_path_to(next)
		_buttons[i].focus_next = _buttons[i].get_path_to(next)

	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return

	# 已经打开 -> ESC 关闭（此时树是暂停的，靠 process_mode=ALWAYS 才收得到）
	if _is_open:
		close()
		get_viewport().set_input_as_handled()
		return

	# 不可暂停的场景（比如开始菜单）自己处理 ESC，这里不插手
	if not _scene_is_pausable():
		return

	# ★ 树已经被别的东西暂停了（典型情况：Game.change_scene() 的淡入淡出期间
	#   paused=true，但 current_scene 还是旧场景、仍在组里）。
	#   这时如果打开暂停菜单，场景切过去之后就会留下一个卡在暂停状态的
	#   新场景（比如一个无法操作的开始菜单）。
	if get_tree().paused:
		return

	open()
	get_viewport().set_input_as_handled()


## 暂停时必须为 true 才能收到输入 —— 用 ALWAYS 而不是 WHEN_PAUSED，
## 因为打开暂停菜单的那一次 ESC 是在"未暂停"状态下发生的。
func _scene_is_pausable() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.is_in_group(PAUSABLE_GROUP)


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	get_tree().paused = true
	resume_button.grab_focus()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	# ★ 必须主动释放焦点：隐藏的按钮如果还握着焦点，
	#   可能把 Space 当成 ui_accept 吃掉 —— 而 Space 正是玩家的跳跃键。
	for b in _buttons:
		b.release_focus()
	get_tree().paused = false


func _draw() -> void:
	# 1) 整屏压暗：让背后的游戏还看得见，读作"暂停"而不是"切走"
	draw_rect(Rect2(0.0, 0.0, CANVAS_W, CANVAS_H), COLOR_DIM)

	# 2) 像素面板：1px 外框 + 1px 斜面 + 填充，和 PixelButton 同一套视觉语言
	draw_rect(PANEL, COLOR_PANEL_EDGE, false, 1.0)
	var inner := PANEL.grow(-1.0)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1.0)), COLOR_BEVEL_LIGHT)
	draw_rect(Rect2(inner.position, Vector2(1.0, inner.size.y)), COLOR_BEVEL_LIGHT)
	draw_rect(Rect2(Vector2(inner.position.x, inner.end.y - 1.0), Vector2(inner.size.x, 1.0)), COLOR_BEVEL_DARK)
	draw_rect(Rect2(Vector2(inner.end.x - 1.0, inner.position.y), Vector2(1.0, inner.size.y)), COLOR_BEVEL_DARK)
	draw_rect(inner.grow(-1.0), COLOR_PANEL_FILL)


## 退出当前对局的统一收尾：解除暂停 + 重置全局状态。
## "重新开始"和"返回主菜单"都要走这一步 —— 漏掉 close() 的话，
## 新场景一进树就是暂停状态（点不动）；漏掉 reset() 的话，
## 灵魂态重开会在死亡世界里出生。
func _reset_and_unpause() -> void:
	close()
	Game.reset()
	Game.player_stats.reset()


## 重新开始：把当前关卡从头加载一遍。
## 注意这会丢掉本局的所有世界状态（玩家留下的尸体、扔出去的石子）——
## 这正是"重新开始"该有的语义，和"返回主菜单"的区别只是加载哪个场景。
func _on_restart() -> void:
	var scene := get_tree().current_scene
	var path := ""
	if scene != null:
		path = scene.scene_file_path

	_reset_and_unpause()

	if path.is_empty():
		# 极端情况：当前场景不是从文件加载的（例如临时搭建的测试场景），
		# 没有路径可以切，退回到引擎自带的重载。
		get_tree().reload_current_scene()
	else:
		# 复用带淡入淡出的转场；entry_point 传空串 = 沿用场景里布置好的出生点
		Game.change_scene(path, "")


func _on_back_to_menu() -> void:
	_reset_and_unpause()
	Game.change_scene(MENU_SCENE, "")


func _on_quit() -> void:
	get_tree().quit()
