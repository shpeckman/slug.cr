// shaders/slug.vert.glsl
// Slug vertex shader: glyph instance expansion, dynamic dilation and glyph data unpacking.
// Dilation derived from the Slug reference vertex shader, Copyright 2017 Eric Lengyel, MIT License.
// Compiled after one of the prelude_*.glsl files.

uniform vec4 slug_matrix[4];   // Rows of the MVP matrix.
uniform vec4 slug_viewport;    // Viewport width and height in pixels.

// Per-instance attributes (one glyph).
layout(location = 0) in vec4 a_rect;     // Em bounds: x min, y min, x max, y max.
layout(location = 1) in vec4 a_xform;    // Em-to-object linear part a, b, c, d.
layout(location = 2) in vec4 a_origin;   // Object translation xy, packed glyph location z, packed band info w.
layout(location = 3) in vec4 a_bnd;      // Band scale xy, band offset zw.
layout(location = 4) in vec4 a_col;      // Premultiplied color.
layout(location = 5) in float a_dilation; // Dilation px.

out vec4 v_color;
out vec2 v_texcoord;
flat out vec4 v_banding;
flat out ivec4 v_glyph;
flat out float v_dilation;

// Moves the vertex outward so the bounding polygon grows by half a pixel in
// viewport space and returns the matching em-space sample position. Scaling
// dim by 1 / (2 D) grows it by D pixels instead.
vec2 slug_dilate(vec4 pos, vec4 tex, vec4 jac, vec4 m0, vec4 m1, vec4 m3, vec2 dim, out vec2 vpos)
{
    vec2 n = normalize(pos.zw);
    float s = dot(m3.xy, pos.xy) + m3.w;
    float t = dot(m3.xy, n);

    float u = (s * dot(m0.xy, n) - t * (dot(m0.xy, pos.xy) + m0.w)) * dim.x;
    float v = (s * dot(m1.xy, n) - t * (dot(m1.xy, pos.xy) + m1.w)) * dim.y;

    float s2 = s * s;
    float st = s * t;
    float uv = u * u + v * v;
    vec2 d = pos.zw * (s2 * (st + sqrt(uv)) / (uv - st * st));

    vpos = pos.xy + d;
    return vec2(tex.x + dot(d, jac.xy), tex.y + dot(d, jac.zw));
}

void main()
{
    // Strip corner: bit 0 selects max x, bit 1 selects max y.
    int corner = gl_VertexID & 3;
    vec2 sgn = vec2((corner & 1) != 0 ? 1.0 : -1.0, (corner & 2) != 0 ? 1.0 : -1.0);
    vec2 em = vec2(sgn.x < 0.0 ? a_rect.x : a_rect.z, sgn.y < 0.0 ? a_rect.y : a_rect.w);
    vec2 obj = vec2(a_xform.x * em.x + a_xform.z * em.y, a_xform.y * em.x + a_xform.w * em.y) + a_origin.xy;

    // Inverse Jacobian rows (object -> em) and the corner normal n with
    // n.u1 = n.u2 = 1 for the unit outward normals u1, u2 of the adjacent sides.
    float det = a_xform.x * a_xform.w - a_xform.z * a_xform.y;
    vec4 jac = vec4(a_xform.w, -a_xform.z, -a_xform.y, a_xform.x) / det;
    vec2 u1 = normalize(jac.xy * sgn.x);
    vec2 u2 = normalize(jac.zw * sgn.y);
    float ndet = u1.x * u2.y - u1.y * u2.x;
    vec2 normal = vec2(u2.y - u1.y, u1.x - u2.x) / ndet;

    // Grow by half a pixel plus any positive dilation.
    float grow = 0.5 + max(a_dilation, 0.0);

    vec2 p;
    v_texcoord = slug_dilate(vec4(obj, normal), vec4(em, a_origin.zw), jac,
                             slug_matrix[0], slug_matrix[1], slug_matrix[3], slug_viewport.xy / (2.0 * grow), p);

    gl_Position = vec4(dot(slug_matrix[0].xy, p) + slug_matrix[0].w,
                       dot(slug_matrix[1].xy, p) + slug_matrix[1].w,
                       dot(slug_matrix[2].xy, p) + slug_matrix[2].w,
                       dot(slug_matrix[3].xy, p) + slug_matrix[3].w);

    uvec2 g = floatBitsToUint(a_origin.zw);
    v_glyph = ivec4(int(g.x & 0xFFFFu), int(g.x >> 16u), int(g.y & 0xFFFFu), int(g.y >> 16u));
    v_banding = a_bnd;
    v_color = a_col;
    v_dilation = a_dilation;
}
