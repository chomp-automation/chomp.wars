shader_type spatial;
render_mode cull_disabled, specular_disabled;
// The inside of the mascot's mouth. The Blender mascot builds this from shader nodes, which
// glTF does not export, so it is rebuilt here: a glow that is black at the back of the bite,
// dim in the middle and bright at the lips, with a bright band just inside the lip and a
// round black throat at the back. It runs in the mesh's own space: +x points out of the
// mouth (back corner to lips), y is up and z is across.

uniform vec3 glow_color : source_color = vec3(0.001, 0.42, 0.48);
uniform float brightness = 2.0;
uniform float back_x = 0.29;  // the back corner of the bite
uniform float lip_x = 1.15;   // the lips
uniform vec3 throat_center = vec3(0.35, -0.15, 0.0);
uniform float throat_radius = 0.68;
uniform float throat_soft = 0.35;  // 0 = hard edge, 1 = fades from the centre
uniform float rim_pos = 0.775;  // where the bright band sits: 1 = at the lip
uniform float rim_boost = 1.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float t = clamp((local_pos.x - back_x) / (lip_x - back_x), 0.0, 1.0);
	// Black at the back, 35% in the middle, full colour at the lips.
	float ramp = t < 0.644 ? mix(0.0, 0.35, t / 0.644) : mix(0.35, 1.0, (t - 0.644) / 0.356);
	float band = 1.0 + rim_boost * max(0.0, 1.0 - abs(t - rim_pos) / 0.2);
	float d = distance(local_pos, throat_center);
	float throat = smoothstep(throat_radius * (1.0 - throat_soft), throat_radius, d);
	ALBEDO = vec3(0.0);
	ROUGHNESS = 0.9;
	EMISSION = glow_color * ramp * band * throat * brightness;
}
