shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float row_count = 45.0;
	float row = clamp(floor(UV.y * row_count), 0.0, row_count - 1.0);
	float reveal_at = (row_count - row) / row_count;
	COLOR = vec4(0.0, 0.0, 0.0, 1.0 - step(reveal_at, progress));
}
