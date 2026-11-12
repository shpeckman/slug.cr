// shaders/slug.slang
// Slug entry points: glyph instance expansion with dynamic dilation, and winding-number coverage
// in a plain and an effects (dilation) fragment variant.
// Dilation derived from the Slug reference vertex shader, Copyright 2017 Eric Lengyel, MIT License.

import curves;
import effects;

// Per-draw parameters, std140 at uniform block binding 2.
struct Params
{
    float4 matrix[4]; // Rows of the MVP matrix.
    float4 viewport;  // Viewport width and height in pixels.
};

[[vk::binding(2)]] ConstantBuffer<Params> params;

// Per-instance attributes (one glyph).
struct Instance
{
    [[vk::location(0)]] float4 rect : RECT;         // Em bounds: x min, y min, x max, y max.
    [[vk::location(1)]] float4 xform : XFORM;       // Em-to-object linear part a, b, c, d.
    [[vk::location(2)]] float4 origin : ORIGIN;     // Object translation xy, packed glyph location z, packed band info w.
    [[vk::location(3)]] float4 bnd : BANDING;       // Band scale xy, band offset zw.
    [[vk::location(4)]] float4 color : COLOR;       // Premultiplied color.
    [[vk::location(5)]] float dilation : DILATION;  // Dilation px.
};

struct Varyings
{
    float4 position : SV_Position;
    float4 color : COLOR;
    float2 texcoord : TEXCOORD;
    nointerpolation float4 banding : BANDING;
    nointerpolation int4 glyph : GLYPH;
    nointerpolation float dilation : DILATION;
};

// Moves the vertex outward so the bounding polygon grows by half a pixel in viewport space and
// returns the matching em-space sample position. Scaling dim by 1 / (2 D) grows it by D pixels
// instead.
float2 dilate(float4 pos, float4 tex, float4 jac, float4 m0, float4 m1, float4 m3, float2 dim, out float2 vpos)
{
    float2 n = normalize(pos.zw);
    float s = dot(m3.xy, pos.xy) + m3.w;
    float t = dot(m3.xy, n);

    float u = (s * dot(m0.xy, n) - t * (dot(m0.xy, pos.xy) + m0.w)) * dim.x;
    float v = (s * dot(m1.xy, n) - t * (dot(m1.xy, pos.xy) + m1.w)) * dim.y;

    float s2 = s * s;
    float st = s * t;
    float uv = u * u + v * v;
    float2 d = pos.zw * (s2 * (st + sqrt(uv)) / (uv - st * st));

    vpos = pos.xy + d;
    return float2(tex.x + dot(d, jac.xy), tex.y + dot(d, jac.zw));
}

[shader("vertex")]
Varyings vertex_main(Instance a, uint vertex_id : SV_VertexID)
{
    // Strip corner: bit 0 selects max x, bit 1 selects max y.
    int corner = int(vertex_id) & 3;
    float2 sgn = float2((corner & 1) != 0 ? 1.0 : -1.0, (corner & 2) != 0 ? 1.0 : -1.0);
    float2 em = float2(sgn.x < 0.0 ? a.rect.x : a.rect.z, sgn.y < 0.0 ? a.rect.y : a.rect.w);
    float2 obj = float2(a.xform.x * em.x + a.xform.z * em.y, a.xform.y * em.x + a.xform.w * em.y) + a.origin.xy;

    // Inverse Jacobian rows (object -> em) and the corner normal n with
    // n.u1 = n.u2 = 1 for the unit outward normals u1, u2 of the adjacent sides.
    float det = a.xform.x * a.xform.w - a.xform.z * a.xform.y;
    float4 jac = float4(a.xform.w, -a.xform.z, -a.xform.y, a.xform.x) / det;
    float2 u1 = normalize(jac.xy * sgn.x);
    float2 u2 = normalize(jac.zw * sgn.y);
    float ndet = u1.x * u2.y - u1.y * u2.x;
    float2 normal = float2(u2.y - u1.y, u1.x - u2.x) / ndet;

    // Grow by half a pixel plus any positive dilation.
    float grow = 0.5 + max(a.dilation, 0.0);

    Varyings o;
    float2 p;
    o.texcoord = dilate(float4(obj, normal), float4(em, a.origin.zw), jac, params.matrix[0], params.matrix[1],
                        params.matrix[3], params.viewport.xy / (2.0 * grow), p);

    o.position = float4(dot(params.matrix[0].xy, p) + params.matrix[0].w,
                        dot(params.matrix[1].xy, p) + params.matrix[1].w,
                        dot(params.matrix[2].xy, p) + params.matrix[2].w,
                        dot(params.matrix[3].xy, p) + params.matrix[3].w);

    uint2 g = asuint(a.origin.zw);
    o.glyph = int4(int(g.x & 0xFFFFu), int(g.x >> 16u), int(g.y & 0xFFFFu), int(g.y >> 16u));
    o.banding = a.bnd;
    o.color = a.color;
    o.dilation = a.dilation;
    return o;
}

float2 pixels_per_em(float2 texcoord)
{
    return 1.0 / (abs(ddx(texcoord)) + abs(ddy(texcoord)));
}

[shader("fragment")]
float4 fragment_main(Varyings v) : SV_Target
{
    return v.color * render(v.texcoord, pixels_per_em(v.texcoord), v.banding, v.glyph);
}

// Variant for draws with any dilated instance.
[shader("fragment")]
float4 fragment_effects(Varyings v) : SV_Target
{
    return v.color * render_effects(v.texcoord, pixels_per_em(v.texcoord), v.banding, v.glyph, v.dilation);
}
