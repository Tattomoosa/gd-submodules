@tool
extends MenuButton

signal import_local

var import_local_index := 0
var disable_plugin_index := 2

func _ready() -> void:
	var popup := get_popup()
	popup.id_pressed.connect(_handle_popup_pressed)

func _handle_popup_pressed(id: int):
	match id:
		import_local_index:
			import_local.emit()
		disable_plugin_index:
			EditorInterface.set_plugin_enabled("tattomoosa/git_submodule_plugin", false)
