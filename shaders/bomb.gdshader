shader_type canvas_item;

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 0.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base_color = COLOR;
	
	float border_thickness = progress * 0.5; 
		
	// Sprawdzamy, czy dany piksel znajduje się przy krawędzi (wewnątrz marginesu)
	if (UV.x < border_thickness || UV.x > 1.0 - border_thickness || UV.y < border_thickness || UV.y > 1.0 - border_thickness) {
		COLOR = line_color;
	} else {
		COLOR = base_color;
	}
}