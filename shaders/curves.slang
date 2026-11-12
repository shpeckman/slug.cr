// shaders/curves.slang
// Glyph curve and band data, ray roots and the reference coverage.
// Coverage derived from the Slug reference pixel shader, Copyright 2017 Eric Lengyel, MIT License.
module curves;

[[vk::binding(0)]] public Sampler2D<float4> slug_curve; // RGBA16F control points.
[[vk::binding(1)]] public Sampler2D<uint4> slug_band;   // RG16UI band data.

static const int kLogBandTextureWidth = 12;

// Band texel at loc: curve count and offset, or a curve location.
public uint2 band_texel(int2 loc)
{
    return slug_band.Load(int3(loc, 0)).xy;
}

// Control points of the curve at curve_loc relative to coord: p1 and p2 in p12, p3.
public void curve_points(int2 curve_loc, float2 coord, out float4 p12, out float2 p3)
{
    p12 = slug_curve.Load(int3(curve_loc, 0)) - float4(coord, coord);
    p3 = slug_curve.Load(int3(curve_loc.x + 1, curve_loc.y, 0)).xy - coord;
}

// Root eligibility from the signs of the sample-relative control point coordinates.
// Bit 0 enables the first root, bit 8 the second.
public uint root_code(float y1, float y2, float y3)
{
    uint i1 = asuint(y1) >> 31u;
    uint i2 = asuint(y2) >> 30u;
    uint i3 = asuint(y3) >> 29u;

    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);
    return (0x2E74u >> shift) & 0x0101u;
}

// x coordinates where the curve crosses y = 0. Imaginary roots collapse to the extremum.
public float2 solve_horiz(float4 p12, float2 p3)
{
    float2 a = p12.xy - p12.zw * 2.0 + p3;
    float2 b = p12.xy - p12.zw;
    float ra = 1.0 / a.y;
    float rb = 0.5 / b.y;

    float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    float t1 = (b.y - d) * ra;
    float t2 = (b.y + d) * ra;

    if (abs(a.y) < 1.0 / 65536.0)
    {
        t1 = p12.y * rb;
        t2 = t1;
    }

    return float2((a.x * t1 - b.x * 2.0) * t1 + p12.x, (a.x * t2 - b.x * 2.0) * t2 + p12.x);
}

// y coordinates where the curve crosses x = 0.
public float2 solve_vert(float4 p12, float2 p3)
{
    float2 a = p12.xy - p12.zw * 2.0 + p3;
    float2 b = p12.xy - p12.zw;
    float ra = 1.0 / a.x;
    float rb = 0.5 / b.x;

    float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
    float t1 = (b.x - d) * ra;
    float t2 = (b.x + d) * ra;

    if (abs(a.x) < 1.0 / 65536.0)
    {
        t1 = p12.x * rb;
        t2 = t1;
    }

    return float2((a.y * t1 - b.y * 2.0) * t1 + p12.y, (a.y * t2 - b.y * 2.0) * t2 + p12.y);
}

// Offsets past the end of a row wrap to the next row.
public int2 band_loc(int2 glyph_loc, uint offset)
{
    int2 loc = int2(glyph_loc.x + int(offset), glyph_loc.y);
    loc.y += loc.x >> kLogBandTextureWidth;
    loc.x &= (1 << kLogBandTextureWidth) - 1;
    return loc;
}

// Coverage of an accumulated winding by the glyph's fill rule (flag 0x1000 even-odd) and optical
// weight (flag 0x2000).
public float fill_rule(float coverage, int flags)
{
    if ((flags & 0x1000) == 0)
        coverage = clamp(coverage, 0.0, 1.0);                       // nonzero
    else
        coverage = 1.0 - abs(1.0 - frac(coverage * 0.5) * 2.0);     // even-odd

    if ((flags & 0x2000) != 0) coverage = sqrt(coverage);            // optical weight

    return coverage;
}

// Away from edges both rays must agree (min).
float coverage(float xcov, float ycov, float xwgt, float ywgt, int flags)
{
    float agreed = min(abs(xcov), abs(ycov));
    return fill_rule(max(abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0), agreed), flags);
}

// Reference coverage of the sample at render_coord: each root r (in pixels along the ray)
// contributes clamp(r + 0.5), a one-pixel box filter.
public float render(float2 render_coord, float2 pixels_per_em, float4 band_transform, int4 glyph_data)
{
    int2 band_max = int2(glyph_data.z, glyph_data.w & 0x00FF);
    int2 band_index = clamp(int2(render_coord * band_transform.xy + band_transform.zw), int2(0, 0), band_max);
    int2 glyph_loc = glyph_data.xy;

    float xcov = 0.0;
    float xwgt = 0.0;

    uint2 hband_data = band_texel(int2(glyph_loc.x + band_index.y, glyph_loc.y));
    int2 hband_loc = band_loc(glyph_loc, hband_data.y);

    for (int curve_index = 0; curve_index < int(hband_data.x); curve_index++)
    {
        int2 curve_loc = int2(band_texel(int2(hband_loc.x + curve_index, hband_loc.y)));
        float4 p12;
        float2 p3;
        curve_points(curve_loc, render_coord, p12, p3);

        // Curves are sorted by descending max x; the rest lie left of the pixel.
        if (max(max(p12.x, p12.z), p3.x) * pixels_per_em.x < -0.5) break;

        uint code = root_code(p12.y, p12.w, p3.y);
        if (code != 0u)
        {
            float2 r = solve_horiz(p12, p3) * pixels_per_em.x;

            if ((code & 1u) != 0u)
            {
                xcov += clamp(r.x + 0.5, 0.0, 1.0);
                xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
            }
            if (code > 1u)
            {
                xcov -= clamp(r.y + 0.5, 0.0, 1.0);
                xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
            }
        }
    }

    float ycov = 0.0;
    float ywgt = 0.0;

    uint2 vband_data = band_texel(int2(glyph_loc.x + band_max.y + 1 + band_index.x, glyph_loc.y));
    int2 vband_loc = band_loc(glyph_loc, vband_data.y);

    for (int curve_index = 0; curve_index < int(vband_data.x); curve_index++)
    {
        int2 curve_loc = int2(band_texel(int2(vband_loc.x + curve_index, vband_loc.y)));
        float4 p12;
        float2 p3;
        curve_points(curve_loc, render_coord, p12, p3);

        // Curves are sorted by descending max y; the rest lie below the pixel.
        if (max(max(p12.y, p12.w), p3.y) * pixels_per_em.y < -0.5) break;

        uint code = root_code(p12.x, p12.z, p3.x);
        if (code != 0u)
        {
            float2 r = solve_vert(p12, p3) * pixels_per_em.y;

            if ((code & 1u) != 0u)
            {
                ycov -= clamp(r.x + 0.5, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
            }
            if (code > 1u)
            {
                ycov += clamp(r.y + 0.5, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
            }
        }
    }

    return coverage(xcov, ycov, xwgt, ywgt, glyph_data.w);
}
