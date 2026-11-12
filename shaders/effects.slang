// shaders/effects.slang
// Dilation effects: true outline offset and the cheaper edge shift. Only the effects fragment
// entry point imports this module, so it never costs registers in the plain shader.
module effects;

import curves;

// Fill of a winding number: 1 inside, 0 outside (nonzero or even-odd rule).
float fill(float winding, bool even_odd)
{
    return even_odd ? fmod(abs(winding), 2.0) : min(abs(winding), 1.0);
}

// Nearest point of a quadratic Bezier to the origin, in pixels, and its squared distance.
struct Nearest
{
    float distance2;
    float2 point;
};

// The closest t solves t^3 + 3 kx t^2 + 3 ky t + kz = 0 (Cardano; with three real roots the
// trigonometric form, whose middle root is never the minimum).
Nearest quad_nearest(float2 p0, float2 p1, float2 p2)
{
    float2 a = p1 - p0;
    float2 b = p0 - 2.0 * p1 + p2;
    float2 c = a * 2.0;
    float2 e = p2 - p0;
    float t;
    float2 point;
    // Collinear control points (lines are stored with a doubled end point): the segment p0 p2.
    if (abs(a.x * e.y - a.y * e.x) <= 1.0e-5 * (dot(a, a) + dot(e, e)))
    {
        t = clamp(-dot(p0, e) / max(dot(e, e), 1.0e-20), 0.0, 1.0);
        point = p0 + e * t;
    }
    else
    {
        float kk = 1.0 / dot(b, b);
        float kx = kk * dot(a, b);
        float ky = kk * (2.0 * dot(a, a) + dot(p0, b)) / 3.0;
        float kz = kk * dot(p0, a);
        float p = ky - kx * kx;
        float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
        float h = q * q + 4.0 * p * p * p;
        if (h >= 0.0)
        {
            h = sqrt(h);
            float2 x = (float2(h, -h) - q) * 0.5;
            float2 uv = sign(x) * pow(abs(x), float2(1.0 / 3.0));
            t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        }
        else
        {
            float z = sqrt(-p);
            float v = acos(q / (p * z * 2.0)) / 3.0;
            float m = cos(v);
            float n = sin(v) * 1.732050808;
            float2 ts = clamp(float2(m + m, -n - m) * z - kx, 0.0, 1.0);
            float2 r0 = p0 + (c + b * ts.x) * ts.x;
            float2 r1 = p0 + (c + b * ts.y) * ts.y;
            t = dot(r0, r0) <= dot(r1, r1) ? ts.x : ts.y;
        }
        point = p0 + (c + b * t) * t;
    }
    Nearest nearest;
    nearest.distance2 = dot(point, point);
    nearest.point = point;
    return nearest;
}

// Winding number at coord from the horizontal ray of its band (crossings to the right).
float winding(float2 coord, float4 band_transform, int4 glyph_data)
{
    int band = clamp(int(coord.y * band_transform.y + band_transform.w), 0, glyph_data.w & 0x00FF);
    uint2 band_data = band_texel(int2(glyph_data.x + band, glyph_data.y));
    int2 loc = band_loc(glyph_data.xy, band_data.y);
    float winding = 0.0;
    for (int curve_index = 0; curve_index < int(band_data.x); curve_index++)
    {
        int2 curve_loc = int2(band_texel(int2(loc.x + curve_index, loc.y)));
        float4 p12;
        float2 p3;
        curve_points(curve_loc, coord, p12, p3);
        if (max(max(p12.x, p12.z), p3.x) < 0.0) break; // the rest cannot cross the ray to the right
        uint code = root_code(p12.y, p12.w, p3.y);
        if (code != 0u)
        {
            float2 r = solve_horiz(p12, p3);
            if ((code & 1u) != 0u && r.x > 0.0) winding += 1.0;
            if (code > 1u && r.y > 0.0) winding -= 1.0;
        }
    }
    return winding;
}

// Whether a curve's nearest point lies on the boundary of the filled region, so that curves hidden
// inside the fill by overlapping, touching or repeated contours do not count. From outside the fill
// the nearest curve always bounds it (anything hidden lies behind the boundary). From inside, the
// fill just past the nearest point (0.25 px further from the sample) must differ.
bool on_boundary(Nearest nearest, bool inside, bool even_odd, float2 render_coord, float2 pixels_per_em,
                 float4 band_transform, int4 glyph_data)
{
    if (!inside) return true;
    float2 probe = nearest.point * (1.0 + 0.25 / max(sqrt(nearest.distance2), 1.0e-6));
    return fill(winding(render_coord + probe / pixels_per_em, band_transform, glyph_data), even_odd) == 0.0;
}

// Squared pixel distance to the nearest curve within reach (reach^2 when none). With `checked` (the
// sample is inside), only boundary curves count (on_boundary). Curves within reach can lie in
// neighboring bands, so all horizontal bands within reach are searched; horizontal lines, which
// horizontal bands leave out, come from the sample's own vertical band.
float nearest_curve2(float2 render_coord, float2 pixels_per_em, float4 band_transform, int4 glyph_data, float reach,
                     bool checked)
{
    int2 band_max = int2(glyph_data.z, glyph_data.w & 0x00FF);
    int2 glyph_loc = glyph_data.xy;
    bool even_odd = (glyph_data.w & 0x1000) != 0;
    float reach_em = reach / pixels_per_em.y;
    int lo = clamp(int((render_coord.y - reach_em) * band_transform.y + band_transform.w), 0, band_max.y);
    int hi = clamp(int((render_coord.y + reach_em) * band_transform.y + band_transform.w), 0, band_max.y);

    float best = reach * reach;
    for (int band = lo; band <= hi; band++)
    {
        uint2 band_data = band_texel(int2(glyph_loc.x + band, glyph_loc.y));
        int2 loc = band_loc(glyph_loc, band_data.y);

        for (int curve_index = 0; curve_index < int(band_data.x); curve_index++)
        {
            int2 curve_loc = int2(band_texel(int2(loc.x + curve_index, loc.y)));
            float4 p12;
            float2 p3;
            curve_points(curve_loc, render_coord, p12, p3);
            float4 q12 = p12 * pixels_per_em.xyxy;
            float2 q3 = p3 * pixels_per_em;

            // Sorted by descending max x: the rest lie further left than the reach.
            if (max(max(q12.x, q12.z), q3.x) < -reach) break;

            float2 gap = max(max(min(min(q12.xy, q12.zw), q3), -max(max(q12.xy, q12.zw), q3)), 0.0);
            if (dot(gap, gap) >= best) continue;
            Nearest nearest = quad_nearest(q12.xy, q12.zw, q3);
            if (nearest.distance2 < best
                && (!checked || on_boundary(nearest, true, even_odd, render_coord, pixels_per_em, band_transform,
                                            glyph_data)))
                best = nearest.distance2;
        }
    }

    // Horizontal lines: where the sample lies within a line's x span, the vertical gap is the distance;
    // elsewhere the nearest point is a line end, shared with a neighboring curve found above. Lines
    // spanning the sample's x are all in its own vertical band.
    int column = clamp(int(render_coord.x * band_transform.x + band_transform.z), 0, band_max.x);
    uint2 column_data = band_texel(int2(glyph_loc.x + band_max.y + 1 + column, glyph_loc.y));
    int2 column_loc = band_loc(glyph_loc, column_data.y);
    for (int curve_index = 0; curve_index < int(column_data.x); curve_index++)
    {
        int2 curve_loc = int2(band_texel(int2(column_loc.x + curve_index, column_loc.y)));
        float4 p12;
        float2 p3;
        curve_points(curve_loc, render_coord, p12, p3);

        // Sorted by descending max y: the rest lie further below than the reach.
        if (max(max(p12.y, p12.w), p3.y) * pixels_per_em.y < -reach) break;
        if (p12.y != p12.w || p12.y != p3.y || min(p12.x, p3.x) > 0.0 || max(p12.x, p3.x) < 0.0) continue;

        float gap = p12.y * pixels_per_em.y;
        Nearest line;
        line.distance2 = gap * gap;
        line.point = float2(0.0, gap);
        if (line.distance2 < best
            && (!checked || on_boundary(line, true, even_odd, render_coord, pixels_per_em, band_transform, glyph_data)))
            best = line.distance2;
    }
    return best;
}

// Thinning, and growth of a pixel or more: the outline offset by `dilation` pixels in every
// direction, so corners grow round and thinning removes exactly the strip along the edges. Coverage
// is clamp(0.5 + dilation - s), s the signed distance in pixels to the nearest boundary curve
// (negative inside). The winding comes first and ends the work where no edge can reach (inside when
// growing by half a pixel or more, outside when thinning by that much). Outside the fill every curve
// bounds it; inside, hidden curves must be skipped at the cost of a winding probe per candidate, so
// the checked search runs only where an edge can matter.
float render_offset(float2 render_coord, float2 pixels_per_em, float4 band_transform, int4 glyph_data, float dilation)
{
    bool even_odd = (glyph_data.w & 0x1000) != 0;
    float reach = abs(dilation) + 0.5;
    bool inside = fill(winding(render_coord, band_transform, glyph_data), even_odd) != 0.0;
    if (inside ? dilation >= 0.5 : dilation <= -0.5) return inside ? 1.0 : 0.0;

    float distance2 = nearest_curve2(render_coord, pixels_per_em, band_transform, glyph_data, reach, false);
    if (inside && (dilation > 0.0 ? sqrt(distance2) >= 0.5 - dilation : distance2 >= reach * reach)) return 1.0;
    if (inside)
        distance2 = nearest_curve2(render_coord, pixels_per_em, band_transform, glyph_data, reach, true);

    float distance = sqrt(distance2);
    float coverage = clamp(0.5 + dilation - (inside ? -distance : distance), 0.0, 1.0);
    if ((glyph_data.w & 0x2000) != 0) coverage = sqrt(coverage);
    return coverage;
}

// One ray of render_shift (vertical rays run on swapped coordinates): roots shifted outward by
// `shift` pixels, each contributing clamp(r + 0.5) with its sign, as in render.
float shift_ray(float2 coord, float ppe, float4 band_transform, int4 glyph_data, bool vertical, float shift,
                float reach)
{
    int2 band_max = int2(glyph_data.z, glyph_data.w & 0x00FF);
    int2 band_index = clamp(int2(coord * band_transform.xy + band_transform.zw), int2(0, 0), band_max);
    int2 glyph_loc = glyph_data.xy;
    int header = vertical ? band_max.y + 1 + band_index.x : band_index.y;
    uint2 band_data = band_texel(int2(glyph_loc.x + header, glyph_loc.y));
    int2 loc = band_loc(glyph_loc, band_data.y);
    float sgn = vertical ? -1.0 : 1.0;

    float coverage = 0.0;
    for (int curve_index = 0; curve_index < int(band_data.x); curve_index++)
    {
        int2 curve_loc = int2(band_texel(int2(loc.x + curve_index, loc.y)));
        float4 p12;
        float2 p3;
        curve_points(curve_loc, coord, p12, p3);
        if (vertical)
        {
            p12 = p12.yxwz;
            p3 = p3.yx;
        }
        if (max(max(p12.x, p12.z), p3.x) * ppe < reach) break;

        uint code = root_code(p12.y, p12.w, p3.y);
        if (code == 0u) continue;
        float2 r = solve_horiz(p12, p3) * ppe + float2(-shift, shift) * sgn;
        if ((code & 1u) != 0u) coverage += sgn * clamp(r.x + 0.5, 0.0, 1.0);
        if (code > 1u) coverage -= sgn * clamp(r.y + 0.5, 0.0, 1.0);
    }
    return coverage;
}

// Growth below one pixel (bold): edges shift outward along the horizontal and vertical ray, and
// either ray's span counts (max). Shifted outward, intervals only widen, so the winding sums stay
// valid with overlapping contours. Corners differ from the true offset of render_offset by under a
// third of a pixel, at a fraction of its cost. Thinning always takes render_offset: shifted inward,
// the two copies of an edge shared by touching contours would open a gap.
float render_shift(float2 render_coord, float2 pixels_per_em, float4 band_transform, int4 glyph_data, float dilation)
{
    float shift = (glyph_data.w & 0x8000) != 0 ? dilation : -dilation;
    float reach = -0.5 - dilation;
    float across = shift_ray(render_coord, pixels_per_em.x, band_transform, glyph_data, false, shift, reach);
    float down = shift_ray(render_coord, pixels_per_em.y, band_transform, glyph_data, true, shift, reach);
    return fill_rule(max(abs(across), abs(down)), glyph_data.w);
}

// Coverage with dilation: the shift below one pixel of growth, the true offset otherwise, the
// reference coverage without dilation.
public float render_effects(float2 render_coord, float2 pixels_per_em, float4 band_transform, int4 glyph_data,
                            float dilation)
{
    if (dilation > 0.0 && dilation < 1.0)
        return render_shift(render_coord, pixels_per_em, band_transform, glyph_data, dilation);
    if (dilation != 0.0)
        return render_offset(render_coord, pixels_per_em, band_transform, glyph_data, dilation);
    return render(render_coord, pixels_per_em, band_transform, glyph_data);
}
