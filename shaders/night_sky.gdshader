shader_type sky;

// A black night sky with stars, a faint Milky Way band and a few distant galaxies.
// Used as the game's sky (see scenes/Environment.tscn). Everything is generated from
// maths, so no texture files are needed.

uniform float star_density : hint_range(40.0, 200.0) = 110.0;
uniform float star_chance : hint_range(0.0, 1.0) = 0.12;
uniform float star_brightness : hint_range(0.0, 3.0) = 1.0;
uniform float galaxy_brightness : hint_range(0.0, 2.0) = 0.9;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x00 = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float x10 = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float x01 = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float x11 = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

// Stars: the sphere of directions is cut into small cells and some cells hold one star.
vec3 stars(vec3 dir) {
	vec3 g = dir * star_density;
	vec3 cell = floor(g);
	vec3 seed = hash33(cell);
	if (seed.x > star_chance) {
		return vec3(0.0);
	}
	vec3 center = hash33(cell + 7.0) * 0.6 + 0.2;
	float d = length(fract(g) - center);
	float radius = mix(0.10, 0.22, seed.y);
	float core = smoothstep(radius, 0.0, d);
	float brightness = mix(0.35, 1.0, seed.z) * star_brightness;
	// Warm, white or cool stars.
	vec3 tint = mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.85, 1.0), seed.y);
	return tint * core * brightness;
}

// Galaxies: a soft oval glow with a bright core, one per coarse cell in some cells.
// Each cell's galaxy is also drawn by its neighbours' pixels, so no glow is cut at a cell edge.
vec3 galaxy_in_cell(vec3 dir, vec3 cell) {
	vec3 seed = hash33(cell + 3.0);
	if (seed.x < 0.55) {
		return vec3(0.0);
	}
	vec3 center = hash33(cell + 11.0) * 0.6 + 0.2;
	vec3 local = dir * 6.0 - cell - center;
	float d2 = dot(local, local);
	float disc = exp(-d2 * 14.0);
	float core = exp(-d2 * 120.0);
	float arms = 0.6 + 0.4 * value_noise(dir * 40.0 + seed * 10.0);
	vec3 tint = mix(vec3(0.7, 0.6, 1.0), vec3(1.0, 0.8, 0.72), seed.y);
	return tint * (disc * 0.35 * arms + core * 0.8) * galaxy_brightness;
}

vec3 galaxies(vec3 dir) {
	vec3 cell = floor(dir * 6.0);
	vec3 total = vec3(0.0);
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			for (int k = -1; k <= 1; k++) {
				total += galaxy_in_cell(dir, cell + vec3(float(i), float(j), float(k)));
			}
		}
	}
	return total;
}

// A faint, dusty band of light across the sky, like the Milky Way.
vec3 milky_way(vec3 dir) {
	vec3 normal = normalize(vec3(0.3, 0.9, 0.4));
	float band = exp(-pow(dot(dir, normal) / 0.16, 2.0));
	float dust = 0.55 * value_noise(dir * 7.0) + 0.45 * value_noise(dir * 19.0);
	return vec3(0.42, 0.36, 0.62) * band * dust * 0.32;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 color = vec3(0.0);  // black space
	color += milky_way(dir);
	color += galaxies(dir);
	color += stars(dir);
	COLOR = color;
}
