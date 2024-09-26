@tool
extends Button

@export var icon_name : String:
	set(value):
		icon_name = value
		if is_node_ready():
			_set_icon()
@export var theme_name : String = "EditorIcons":
	set(value):
		theme_name = value
		if is_node_ready():
			_set_icon()

func _ready() -> void:
	_set_icon()

func _set_icon() -> void:
	icon = get_theme_icon(icon_name, theme_name)

func _validate_property(property: Dictionary) -> void:
	if property.name == "icon":
		property.usage = PROPERTY_USAGE_NONE | PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR