extends Control

signal typing_completed
signal key_rewritten

@export_range(1, 100) var required_words: int = 10

const WORDS: Array[String] = [
	"sakura", "neko", "sora", "umi", "yama", "kumo", "hoshi", "tsuki",
	"mikan", "ringo", "suika", "tamago", "tsukue", "enpitsu", "hon", "tokei",
	"asagao", "himawari", "kotori", "usagi", "kaze", "midori", "komorebi", "suzume"
]

var current_word_index: int = -1
var completed_words: int = 0
var entered_letters: int = 0
var first_sound: bool = false

@onready var rows: VBoxContainer = $Keyboard/Rows
@onready var prompt: Label = $Prompt
@onready var prompt_progress: Label = $Prompt/Progress


func _ready() -> void:
	first_sound = false
	_pick_next_word()
	prompt.resized.connect(_fit_prompt)
	for row in rows.get_children():
		for child in row.get_children():
			if child is Button:
				child.pressed.connect(_on_key_pressed.bind(child))


func _on_key_pressed(key: Button) -> void:
	if completed_words >= required_words:
		return

	var word: String = WORDS[current_word_index]
	var expected: String = word.substr(entered_letters, 1)
	var letter: String = key.text.to_lower()
	if letter != expected:
		key.text = expected.to_upper()
		key_rewritten.emit()
		return
	
	$TypingSound.play()
	entered_letters += 1
	prompt_progress.visible_characters = entered_letters
	if entered_letters == word.length():
		completed_words += 1
		if completed_words >= required_words:
			typing_completed.emit()
			return
		_pick_next_word()


func _pick_next_word() -> void:
	entered_letters = 0
	if current_word_index < 0:
		current_word_index = randi_range(0, WORDS.size() - 1)
	else:
		# Choose any word except the current one.
		current_word_index = (current_word_index + randi_range(1, WORDS.size() - 1)) % WORDS.size()
	prompt.text = WORDS[current_word_index]
	prompt_progress.text = prompt.text
	prompt_progress.visible_characters = 0
	_fit_prompt()
	if first_sound:
		$QuestionSound.play()
	else:
		first_sound = true	


func _fit_prompt() -> void:
	var available: Vector2 = prompt.size - Vector2(16.0, 16.0)
	if available.x <= 0.0 or available.y <= 0.0:
		return

	var font: Font = prompt.get_theme_font("font")
	var smallest: int = 1
	var largest: int = ceili(available.y * 2.0)
	var best: int = 1
	while smallest <= largest:
		var candidate: int = (smallest + largest) >> 1
		var text_size: Vector2 = font.get_string_size(prompt.text, HORIZONTAL_ALIGNMENT_LEFT, -1, candidate)
		if text_size.x <= available.x and text_size.y <= available.y and font.get_height(candidate) <= available.y:
			best = candidate
			smallest = candidate + 1
		else:
			largest = candidate - 1

	if best != prompt.get_theme_font_size("font_size"):
		prompt.add_theme_font_size_override("font_size", best)
		prompt_progress.add_theme_font_size_override("font_size", best)
