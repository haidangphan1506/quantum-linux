#version 440
// Mưa ký tự kiểu Matrix: 3 lớp độ sâu (xa mờ/nhỏ/chậm, gần sáng/to/nhanh),
// đầu giọt trắng xanh, đuôi mờ dần, vệt sáng dọc cột và ký tự đổi ngẫu nhiên.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 res;
    float cscale;
};
layout(binding = 1) uniform sampler2D atlas;   // 8x8 ký tự trắng trên nền trong suốt

const float GLYPHS = 64.0;
const float ATLAS_N = 8.0;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float glyph(vec2 cell, vec2 uv, float seed) {
    // mỗi ô đổi ký tự với nhịp riêng
    float rate = 0.4 + hash(cell + seed + 7.1) * 2.5;
    float t = floor(time * rate + hash(cell + seed) * 10.0);
    float gi = floor(hash(cell + vec2(t * 0.731, seed)) * GLYPHS);
    vec2 a = (vec2(mod(gi, ATLAS_N), floor(gi / ATLAS_N)) + (uv - 0.5) * vec2(0.72, 0.7) + 0.5) / ATLAS_N;
    return texture(atlas, a).a;
}

// trả về màu cộng dồn của một lớp
vec3 rainLayer(vec2 px, float cw, float speedMul, float seed, float dim, float density) {
    float ch = cw * 1.32;
    vec2 g = vec2(px.x / cw, px.y / ch);
    vec2 cell = floor(g);
    vec2 uv = fract(g);
    float col = cell.x;

    // một số cột trống
    if (hash(vec2(col, seed * 3.7)) > density) return vec3(0.0);

    float rows = res.y / ch;
    vec3 c = vec3(0.0);
    // hai giọt mỗi cột, lệch pha
    for (int k = 0; k < 2; k++) {
        float fk = float(k);
        float r1 = hash(vec2(col, seed + fk * 11.0));
        float r2 = hash(vec2(col + 31.0, seed + fk * 5.0));
        float speed = (5.0 + r1 * 11.0) * speedMul;           // hàng / giây
        float len = 14.0 + r2 * 30.0;                           // độ dài đuôi (hàng)
        float period = rows + len + 8.0 + r1 * rows * 0.8;
        float head = mod(time * speed + r2 * period + fk * period * 0.5, period) - 2.0;
        float d = head - g.y;                                    // > 0: phía sau đầu giọt

        if (d > -0.6 && d < len) {
            float tail = clamp(1.0 - d / len, 0.0, 1.0);
            tail = pow(tail, 1.3);
            float gl = glyph(cell, uv, seed);
            float isHead = smoothstep(1.2, 0.0, abs(d - 0.3));
            vec3 green = vec3(0.08, 1.0, 0.32);
            vec3 white = vec3(0.78, 1.0, 0.86);
            c += gl * mix(green * tail, white, isHead) * (d < 0.0 ? 0.0 : 1.0);
            // vệt sáng mờ phía sau ký tự (giống phim): mạnh gần đầu giọt
            float xw = 1.0 - abs(uv.x - 0.5) * 2.0;
            float streak = pow(max(d, 0.0) < len ? tail : 0.0, 2.5) * xw * xw;
            c += green * streak * 0.45;
        }
        // quầng sáng quanh đầu giọt
        float hx = 1.0 - abs(uv.x - 0.5) * 2.0;
        c += vec3(0.25, 1.0, 0.5) * exp(-abs(d) * 1.1) * hx * 0.45;
    }
    return c * dim;
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    float s = cscale;
    vec3 c = vec3(0.0);
    c += rainLayer(px, 15.0 * s, 0.45, 1.0, 0.28, 0.8);   // xa
    c += rainLayer(px + vec2(5.0, 0.0), 23.0 * s, 0.7, 2.0, 0.6, 0.7);   // giữa
    c += rainLayer(px + vec2(9.0, 0.0), 33.0 * s, 1.0, 3.0, 1.15, 0.65);    // gần
    // nền đen hơi xanh, tối dần ở mép
    vec2 q = qt_TexCoord0 - 0.5;
    float vig = 1.0 - dot(q, q) * 0.9;
    c = c * vig + vec3(0.0, 0.012, 0.004);
    c = 1.0 - exp(-c * 1.8);   // tone map nhẹ để glow không cháy
    fragColor = vec4(c, 1.0) * qt_Opacity;
}
