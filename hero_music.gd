extends AudioStreamPlayer

@onready var starting_volume_db: float = volume_db


func ensure_playing() -> void:
	if playing:
		return

	volume_db = starting_volume_db
	play()
