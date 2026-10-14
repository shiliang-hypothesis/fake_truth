class_name PixelButton
extends Button

## 像素风按钮：边框和填充全部用 draw_rect 手绘，硬边、无抗锯齿。
##
## 为什么不用 StyleBoxFlat + 主题：
##   StyleBoxFlat 的圆角/抗锯齿会把边缘糊掉，破坏点阵观感；
##   这里 1px 外框 + 1px 斜面正好落在画布像素网格上，
##   再被 canvas_items 的 3 倍拉伸放大成 3x3 方块。
##
## 为什么文字放在子节点 Label 上：
##   Button 自身的绘制发生在脚本 _draw() **之前**，
##   如果在这里填色，会把按钮内建画的文字盖住。
##   子节点在父节点之后绘制，所以文字交给 Label 最稳。
##
## 视觉规格（单位 = 逻辑像素，384x216 画布）：
##   1px 外框  |  1px 斜面（上/左受光，下/右背光）  |  填充
## 按下时斜面反转 + 填充换亮色，做出"按进去"的手感。
##
## 聚焦指示三角也画在这里：画在按钮矩形**之外**（局部 x 为负）。
## Control 默认不裁剪自绘内容，所以开始菜单和暂停菜单都能白拿这个指示器，
## 不用各自实现一份。

const PX := 1.0
const MARKER_COLOR := Color("7fe8e4")

@export var show_focus_marker := true

@export var fill_normal := Color("0c2626")
@export var fill_hot := Color("14403f")
@export var fill_pressed := Color("7fe8e4")
@export var fill_disabled := Color("091a1a")

@export var edge_normal := Color("2b6664")
@export var edge_hot := Color("7fe8e4")
@export var bevel_light := Color("74d6d0")
@export var bevel_dark := Color("04100f")

@export var label_normal := Color("cfefec")
@export var label_hot := Color("ffffff")
@export var label_pressed := Color("04181a")
@export var label_disabled := Color("3a5c5c")

var _held := false

@onready var _label: Label = get_node_or_null("Label") as Label


func _ready() -> void:
	# 关掉主题自带的全部样式盒，边框完全由 _draw() 负责
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())

	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _label != null:
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	mouse_entered.connect(_refresh)
	mouse_exited.connect(_refresh)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)

	_refresh()


func _on_button_down() -> void:
	_held = true
	_refresh()


func _on_button_up() -> void:
	_held = false
	_refresh()


func _refresh() -> void:
	if _label != null:
		_label.add_theme_color_override("font_color", _label_color())
	queue_redraw()


## "选中/悬停"：焦点和鼠标都算，键盘和鼠标操作观感一致
func _is_hot() -> bool:
	return has_focus() or is_hovered()


func _label_color() -> Color:
	if disabled:
		return label_disabled
	if _held:
		return label_pressed
	if _is_hot():
		return label_hot
	return label_normal


func _draw() -> void:
	# 取整，保证边框落在像素网格上，不会出现半像素糊边
	var w := floorf(size.x)
	var h := floorf(size.y)
	if w < 4.0 or h < 4.0:
		return
	var r := Rect2(0.0, 0.0, w, h)

	var fill := fill_normal
	var edge := edge_normal
	if disabled:
		fill = fill_disabled
		edge = edge_normal.darkened(0.45)
	elif _held:
		fill = fill_pressed
		edge = edge_hot
	elif _is_hot():
		fill = fill_hot
		edge = edge_hot

	# 1) 外框
	draw_rect(r, edge, false, PX)

	# 2) 斜面：按下时受光/背光对调，读作"凹陷"
	var light := bevel_dark if _held else bevel_light
	var dark := bevel_light if _held else bevel_dark
	var ix := r.position.x + PX
	var iy := r.position.y + PX
	var iw := w - PX * 2.0
	var ih := h - PX * 2.0
	draw_rect(Rect2(ix, iy, iw, PX), light)             # 上
	draw_rect(Rect2(ix, iy, PX, ih), light)             # 左
	draw_rect(Rect2(ix, iy + ih - PX, iw, PX), dark)    # 下
	draw_rect(Rect2(ix + iw - PX, iy, PX, ih), dark)    # 右

	# 3) 填充
	draw_rect(Rect2(ix + PX, iy + PX, iw - PX * 2.0, ih - PX * 2.0), fill)

	# 4) 聚焦指示：按钮左侧的 4x7 像素右三角，行宽 1/2/3/4/3/2/1
	if show_focus_marker and has_focus():
		var my := floorf(h * 0.5) - 3.0
		for row in 7:
			var mw := 4.0 - absf(float(row) - 3.0)
			draw_rect(Rect2(-11.0, my + float(row), mw, 1.0), MARKER_COLOR)
