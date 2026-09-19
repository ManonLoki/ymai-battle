shader_type canvas_item;
render_mode unshaded;

// 同一幅完整场景按高度分成三层深度。这些图不是无缝贴图，所以不做 fract
// 单向循环；改用慢速正弦往返的镜头巡航，既有卷轴感也不会暴露接缝。
uniform float elapsed_seconds = 0.0;
uniform float far_amplitude_px : hint_range(0.0, 64.0) = 8.0;
uniform float mid_amplitude_px : hint_range(0.0, 64.0) = 18.0;
uniform float near_amplitude_px : hint_range(0.0, 64.0) = 30.0;
uniform float scroll_cycle_seconds : hint_range(8.0, 90.0) = 32.0;
uniform float scroll_direction : hint_range(-1.0, 1.0) = 1.0;
uniform float edge_guard_px : hint_range(0.0, 8.0) = 2.0;

void fragment() {
	float cycle_seconds = max(scroll_cycle_seconds, 0.001);
	float pan = sin(elapsed_seconds * TAU / cycle_seconds) * scroll_direction;

	// 宽过渡带把三个景深连成一次同向镜头运动：远景慢，近景快。
	float far_to_mid = smoothstep(0.30, 0.44, UV.y);
	float mid_to_near = smoothstep(0.58, 0.78, UV.y);
	float travel_px = mix(far_amplitude_px, mid_amplitude_px, far_to_mid);
	travel_px = mix(travel_px, near_amplitude_px, mid_to_near);
	float shift_px = pan * travel_px;

	// 按最大行程做等比 overscan，同时裁入 X/Y，避免仅拉宽横向。
	// 余出 guard 后只加水平位移，不需要 clamp 边缘来掩盖露底。
	float max_travel_px = max(far_amplitude_px, max(mid_amplitude_px, near_amplitude_px));
	float inset = (max_travel_px + edge_guard_px) * TEXTURE_PIXEL_SIZE.x;
	float overscan_scale = max(1.0 - 2.0 * inset, 0.001);
	vec2 sample_uv = (UV - vec2(0.5)) * overscan_scale + vec2(0.5);
	sample_uv.x += shift_px * TEXTURE_PIXEL_SIZE.x;

	// 纵向仍落在原图像素中心；横向手动在相邻两像素中心之间混合，
	// 让大幅度慢速巡航不跳格，又不会把整幅像素画变成双线性模糊。
	float source_x = sample_uv.x / TEXTURE_PIXEL_SIZE.x - 0.5;
	float left_x = floor(source_x);
	float horizontal_mix = fract(source_x);
	float source_y = floor(sample_uv.y / TEXTURE_PIXEL_SIZE.y);
	vec2 left_uv = vec2(
		(left_x + 0.5) * TEXTURE_PIXEL_SIZE.x,
		(source_y + 0.5) * TEXTURE_PIXEL_SIZE.y
	);
	vec2 right_uv = left_uv + vec2(TEXTURE_PIXEL_SIZE.x, 0.0);
	COLOR = mix(texture(TEXTURE, left_uv), texture(TEXTURE, right_uv), horizontal_mix);
}
