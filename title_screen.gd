extends Control

const HERO_PROLOGUE_SCENE: PackedScene = preload("res://hero_prologue.tscn")
const AUDIO_SETTINGS_PATH := "user://audio_settings.cfg"

@onready var hero_button: TextureButton = $HeroButton
@onready var settings_button: TextureButton = $Taskbar/Settings
@onready var sound_button: TextureButton = $Taskbar/Sound
@onready var modal: ColorRect = $Modal
@onready var heading: Label = $Modal/Window/Heading
@onready var close_button: Button = $Modal/Window/Close
@onready var credits: Control = $Modal/Window/Credits
@onready var license_text: RichTextLabel = $Modal/Window/Credits/License
@onready var mixer: Control = $Modal/Window/Mixer
@onready var bgm_slider: HSlider = $Modal/Window/Mixer/BGMSlider
@onready var se_slider: HSlider = $Modal/Window/Mixer/SESlider
@onready var bgm_value: Label = $Modal/Window/Mixer/BGMValue
@onready var se_value: Label = $Modal/Window/Mixer/SEValue


func _ready() -> void:
	license_text.text = Engine.get_license_text()
	var font_license: String = FileAccess.get_file_as_string("res://Asset/NotoSansJP-OFL.txt")
	if not font_license.is_empty():
		license_text.text += "\n\nNoto Sans JP\n\n" + font_license
	var saved: ConfigFile = ConfigFile.new()
	saved.load(AUDIO_SETTINGS_PATH)
	bgm_slider.value = clampf(float(saved.get_value("volume", "BGM", 100.0)), 0.0, 100.0)
	se_slider.value = clampf(float(saved.get_value("volume", "SE", 100.0)), 0.0, 100.0)
	bgm_slider.value_changed.connect(_apply_volume.bind(&"BGM", bgm_value))
	se_slider.value_changed.connect(_apply_volume.bind(&"SE", se_value))
	_apply_volume(bgm_slider.value, &"BGM", bgm_value)
	_apply_volume(se_slider.value, &"SE", se_value)


func _unhandled_key_input(event: InputEvent) -> void:
	if modal.visible and event.is_action_pressed("ui_cancel"):
		_close_modal()
		get_viewport().set_input_as_handled()


func _on_settings_pressed() -> void:
	_open_modal(false)


func _on_sound_pressed() -> void:
	_open_modal(true)


func _open_modal(show_mixer: bool) -> void:
	heading.text = "音量調節" if show_mixer else "設定"
	credits.visible = not show_mixer
	mixer.visible = show_mixer
	hero_button.disabled = true
	settings_button.disabled = true
	sound_button.disabled = true
	modal.show()
	close_button.grab_focus()


func _close_modal() -> void:
	var return_focus: TextureButton = sound_button if mixer.visible else settings_button
	if mixer.visible:
		var saved: ConfigFile = ConfigFile.new()
		saved.set_value("volume", "BGM", bgm_slider.value)
		saved.set_value("volume", "SE", se_slider.value)
		var result: Error = saved.save(AUDIO_SETTINGS_PATH)
		if result != OK:
			push_warning("Could not save audio settings: %s" % error_string(result))
	modal.hide()
	hero_button.disabled = false
	settings_button.disabled = false
	sound_button.disabled = false
	return_focus.grab_focus()


func _apply_volume(value: float, bus_name: StringName, value_label: Label) -> void:
	value_label.text = "%d%%" % ceili(value)
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(value / 100.0, 0.0001)))
		AudioServer.set_bus_mute(bus_index, value == 0.0)


func _on_hero_button_pressed() -> void:
	var result: Error = get_tree().change_scene_to_packed(HERO_PROLOGUE_SCENE)
	if result != OK:
		push_error("Could not open the hero prologue: %s" % error_string(result))
