extends ColorRect

const HERO_CLICKER_SCENE: PackedScene = preload("res://main.tscn")
const DIALOGUE: Array[String] = [
	"魔王の封印が解かれ、世界は勇者を待ち侘びていた。",
	"そしてついに、勇者が現れる瞬間が来たのだ。",
	"勇者「再び魔王を封印するため、北の村より参りました。」",
	"王様「うむ。魔王城まではあまりにも遠い。だが、道中ではそなたを応援する者たちに出会うだろう。」",
	"王様「その応援を背に、一歩ずつでも歩みを進めるのだ。」",
]

var line_index: int = 0

@onready var dialogue_line: Label = $Dialogue/Line
@onready var hero_bgm: AudioStreamPlayer = $PrologueBGM


func _ready() -> void:
	dialogue_line.text = DIALOGUE[line_index]
	hero_bgm.play()


func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()

	if line_index + 1 < DIALOGUE.size():
		line_index += 1
		dialogue_line.text = DIALOGUE[line_index]
		return

	var playback_position: float = hero_bgm.get_playback_position()
	hero_bgm.autoplay = false
	remove_child(hero_bgm)
	get_tree().root.add_child(hero_bgm)
	hero_bgm.play(playback_position)
	var result: Error = get_tree().change_scene_to_packed(HERO_CLICKER_SCENE)
	if result != OK:
		get_tree().root.remove_child(hero_bgm)
		add_child(hero_bgm)
		push_error("Could not open the hero clicker: %s" % error_string(result))
