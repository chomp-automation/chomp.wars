shader_type canvas_item;

// The start screen's background: a black night sky with stars, a faint Milky Way band and a
// few galaxies, drawn in screen space. It matches the sky in the game (night_sky.gdshader).

uniform float star_cell : hint_range(16.0, 80.0) = 34.0;
uniform float galaxy_cell : hint_range(200.0, 800.0) = 420.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// One candidate star per cell. Most cells are empty and the rest twinkle slowly.
float star_layer(vec2 px) {
	vec2 cell = floor(px / star_cell);
	float seed = hash21(cell);
	if (seed < 0.82) {
		return 0.0;
	}
	vec2 center = (cell + vec2(hash21(cell + 17.0), hash21(cell + 31.0))) * star_cell;
	float radius = mix(0.8, 1.9, hash21(cell + 5.0));
	float twinkle = 0.7 + 0.3 * sin(TIME * (1.0 + 2.0 * hash21(cell + 9.0)) + seed * 40.0);
	return smoothstep(radius, 0.0, distance(px, center)) * twinkle;
}

// One soft galaxy per coarse cell in some cells. Each cell's galaxy is drawn by the pixels
// of its neighbours too (see galaxy_layer), so a glow is never cut off at a cell edge.
vec3 galaxy_in_cell(vec2 px, vec2 cell) {
	if (hash21(cell + 3.0) < 0.45) {
		return vec3(0.0);
	}
	vec2 center = (cell + vec2(0.2 + 0.6 * hash21(cell + 7.0), 0.2 + 0.6 * hash21(cell + 11.0))) * galaxy_cell;
	float r2 = dot(px - center, px - center);
	float glow = exp(-r2 / (2.0 * 70.0 * 70.0));
	float core = exp(-r2 / (2.0 * 16.0 * 16.0));
	vec3 tint = mix(vec3(0.7, 0.6, 1.0), vec3(1.0, 0.8, 0.72), hash21(cell + 13.0));
	return tint * (glow * 0.2 + core * 0.7);
}

vec3 galaxy_layer(vec2 px) {
	vec2 cell = floor(px / galaxy_cell);
	vec3 total = vec3(0.0);
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			total += galaxy_in_cell(px, cell + vec2(float(i), float(j)));
		}
	}
	return total;
}

void fragment() {
	vec2 px = FRAGCOORD.xy;
	// A faint band of light across the sky, like the Milky Way.
	float band_y = UV.y - 0.55 + 0.25 * (UV.x - 0.5);
	float band = exp(-band_y * band_y / 0.012);
	float dust = 0.6 + 0.4 * sin(UV.x * 23.0 + UV.y * 11.0) * sin(UV.y * 37.0);
	vec3 color = vec3(0.42, 0.36, 0.62) * band * dust * 0.3;
	color += galaxy_layer(px);
	color += vec3(0.92, 0.94, 1.0) * star_layer(px);
	COLOR = vec4(color, 1.0);
}
