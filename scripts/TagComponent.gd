# TagComponent.gd
extends Node
class_name TagComponent #物品标签

signal tags_changed

var tags: Array[String] = []

func add_tag(tag: String) -> void:
	if not tags.has(tag):
		tags.append(tag)
		tags_changed.emit()

func remove_tag(tag: String) -> void:
	if tags.has(tag):
		tags.erase(tag)
		tags_changed.emit()

func has_tag(tag: String) -> bool:
	return tags.has(tag)

func has_any(tag_list: Array) -> bool:
	for t in tag_list:
		if tags.has(t):
			return true
	return false
