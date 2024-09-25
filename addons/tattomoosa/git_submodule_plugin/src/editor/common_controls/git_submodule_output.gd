@tool
extends RichTextLabel

@onready var loading_indicator: Control = %LoadingIndicator

@export var loading: bool:
	set(value):
		loading = value
		if is_node_ready() and loading_indicator:
			loading_indicator.visible = loading

func _ready() -> void:
	add_theme_font_override("normal_font", get_theme_font("output_source_mono", "EditorFonts"))

func print(
	var0: Variant = "",
	var1: Variant = "",
	var2: Variant = "",
	var3: Variant = "",
	var4: Variant = "",
	var5: Variant = "",
	var6: Variant = "",
	var7: Variant = "",
	var8: Variant = "",
) -> void:
	var vars: PackedStringArray = [
		str(var0), str(var1), str(var2), str(var3), str(var4), str(var5), str(var6), str(var7), str(var8),
		"\n"
	]
	var msg := "".join(vars)
	append_text(msg)
