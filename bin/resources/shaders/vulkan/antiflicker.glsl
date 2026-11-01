// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

//#version 420 // Keep it for editor detection

// Anti-flicker: port of the RetroArch shader of the same name.
//   Original by hunterk (public domain), extended and optimized by crashGG.
//
// Detects pixels that alternate between bright and dark every frame (flicker-based
// transparency) and outputs a blend of the current and previous frame for them.
//
// samp0 is the frame-history ring: ANTIFLICKER_SLOTS (6) frames stacked vertically in one
// texture. params0.x is the slot holding the current frame, older frames are the preceding
// slots (wrapping around).

#ifdef VERTEX_SHADER

layout(location = 0) in vec4 a_pos;
layout(location = 1) in vec2 a_tex;

layout(location = 0) out vec2 v_tex;

void main()
{
	gl_Position = vec4(a_pos.x, -a_pos.y, a_pos.z, a_pos.w);
	v_tex = a_tex;
}

#endif

#ifdef FRAGMENT_SHADER

layout(push_constant) uniform cb0
{
	vec4 params0; // x = ring slot of the current frame, y = luma threshold, z = start row, w = end row
	vec4 params1; // x = 1.0 once the ring holds a full set of frames
};

layout(set = 0, binding = 0) uniform sampler2D samp0;
layout(location = 0) in vec2 v_tex;
layout(location = 0) out vec4 o_col0;

const int SLOTS = 6;

// age 0 = current frame, 1 = previous frame, ... 5 = five frames ago
vec4 FetchFrame(int age, int frame_height)
{
	int slot = (int(params0.x + 0.5) - age + SLOTS) % SLOTS;
	ivec2 pos = ivec2(gl_FragCoord.xy) + ivec2(0, slot * frame_height);
	return texelFetch(samp0, pos, 0);
}

// BT.601 luma
float Luma(vec3 c)
{
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void main()
{
	const int frame_height = textureSize(samp0, 0).y / SLOTS;

	vec4 cur = FetchFrame(0, frame_height);
	o_col0 = cur;

	// Not enough history yet (first frames after enabling / a resolution change).
	if (params1.x < 0.5)
		return;

	// Only detect inside [start row, end row] (fractions of the frame height).
	float row = gl_FragCoord.y / float(frame_height);
	if (row < params0.z || row > params0.w)
		return;

	vec3 prev1 = FetchFrame(1, frame_height).rgb;

	float l0 = Luma(cur.rgb);
	float l1 = Luma(prev1);
	float l2 = Luma(FetchFrame(2, frame_height).rgb);
	float l3 = Luma(FetchFrame(3, frame_height).rgb);
	float l4 = Luma(FetchFrame(4, frame_height).rgb);
	float l5 = Luma(FetchFrame(5, frame_height).rgb);

	// Alternating-frame lock: the even or the odd frame sequence must stay constant...
	bool chain024 = abs(l0 - l2) < 0.01 && abs(l2 - l4) < 0.01;
	bool chain135 = abs(l1 - l3) < 0.01 && abs(l3 - l5) < 0.01;

	// ...while consecutive frames differ by more than the threshold, three times in a row.
	bool flicker = (chain024 || chain135)
		&& abs(l0 - l1) > params0.y
		&& abs(l2 - l3) > params0.y
		&& abs(l4 - l5) > params0.y;

	if (flicker)
	{
		// Sum & delta with a floor on the dark end, then a 1st-order Taylor expansion of the
		// original pow()-based blend.
		vec3 sum = max(cur.rgb, vec3(0.05)) + max(prev1, vec3(0.05));
		vec3 inv_sum = vec3(1.0) / sum;
		vec3 diff = cur.rgb - prev1;
		o_col0.rgb = sum * 0.5 + diff * diff * inv_sum * 0.25;
	}
}

#endif
