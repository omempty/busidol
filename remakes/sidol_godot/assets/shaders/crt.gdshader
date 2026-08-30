shader_type canvas_item;
// CRT 모니터 연출 — 04_uiux §1.5 "CRT 스캔라인/휘곡 셰이더".
//
// 이 저장소의 첫 셰이더다(2026-08-30까지 .gdshader 0개). 엔딩 메타 씬(E-2)이
// 1995년 DOS 콘솔로 넘어가는 자리를 위해 만들었다. 화면 전체를 덮는 ColorRect에
// 물려 쓰고, 아래 배경·글자를 screen_texture로 다시 읽어 휘어 그린다.
//
// 값은 전부 uniform이라 씬에서 조절한다 — 세게 걸면 글자가 안 읽힌다.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

// 화면 휘곡(배럴). 0이면 평면.
uniform float curvature : hint_range(0.0, 0.5) = 0.12;
// 주사선 — 굵기(px)와 어둡기.
uniform float scanline_px : hint_range(1.0, 8.0) = 3.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.28;
// 색수차(RGB 어긋남) — 화면 가장자리로 갈수록 커진다.
uniform float aberration : hint_range(0.0, 4.0) = 1.1;
// 네 귀퉁이 어둡기.
uniform float vignette : hint_range(0.0, 1.0) = 0.45;
// 형광체 잔광처럼 보이게 하는 미세한 밝기 요동.
uniform float flicker : hint_range(0.0, 0.2) = 0.03;

// 화면 중심 기준으로 UV를 바깥으로 휜다. 튜브의 곡률을 흉내낸다.
vec2 curve_uv(vec2 uv, float amount) {
	vec2 c = uv * 2.0 - 1.0;
	c *= 1.0 + amount * dot(c.yx, c.yx);
	return c * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = curve_uv(SCREEN_UV, curvature);

	// 튜브 바깥은 검게 — 휘어 나간 자리에 화면이 늘어붙지 않게 한다.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec2 off = (uv - 0.5) * aberration * SCREEN_PIXEL_SIZE;
		vec3 col = vec3(
			texture(screen_tex, uv + off).r,
			texture(screen_tex, uv).g,
			texture(screen_tex, uv - off).b
		);

		// 주사선 — 실제 픽셀 행을 세어 굵기를 정한다(해상도가 바뀌어도 같은 굵기).
		float row = FRAGCOORD.y / max(scanline_px, 1.0);
		float line = 0.5 + 0.5 * cos(row * 6.2831853);
		col *= 1.0 - scanline_strength * line;

		// 비네트 — 중심에서 멀수록 어둡게.
		float d = length(uv - 0.5);
		col *= 1.0 - vignette * smoothstep(0.35, 0.78, d);

		// 잔광 요동 — 아주 약하게. 크면 눈이 피로해진다.
		col *= 1.0 + flicker * sin(TIME * 37.0);

		COLOR = vec4(col, 1.0);
	}
}
