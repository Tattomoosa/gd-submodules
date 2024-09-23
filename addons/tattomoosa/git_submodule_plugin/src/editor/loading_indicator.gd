@tool
extends PanelContainer

var textures : Array[Texture2D]

var texture_index : float = 0

func _ready() -> void:
	for i in range(1, 9):
		textures.push_back(
			get_theme_icon("Progress%d" % i, "EditorIcons")
		)

func _process(delta: float) -> void:
	if visible:
		queue_redraw()
		texture_index += delta * 10
		if texture_index >= 8:
			texture_index = 0

func _draw() -> void:
	var texture := textures[int(texture_index) % 8]
	var tex_size := texture.get_size()
	draw_texture(texture, size / 2 - tex_size)

