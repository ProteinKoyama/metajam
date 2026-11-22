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


func _ready() -> void:
	dialogue_line.text = DIALOGUE[line_index]
	HeroMusic.ensure_playing()


func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()

	if line_index + 1 < DIALOGUE.size():
		line_index += 1
		dialogue_line.text = DIALOGUE[line_index]
		return

	var result: Error = get_tree().change_scene_to_packed(HERO_CLICKER_SCENE)
	if result != OK:
		push_error("Could not open the hero clicker: %s" % error_string(result))
