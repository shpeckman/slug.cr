// shaders/slug.frag.glsl
// Slug pixel shader: winding-number coverage from horizontal and vertical rays, with dilation/softness
// effects. Built twice: plain, and with SLUG_EFFECTS (dilation, softness).
// Coverage derived from the Slug reference pixel shader, Copyright 2017 Eric Lengyel, MIT License.
// Compiled after one of the prelude_*.glsl files.

uniform sampler2D slug_curve;   // RGBA16F control points.
uniform usampler2D slug_band;   // RG16UI band data.

in vec4 v_color;
in vec2 v_texcoord;
flat in vec4 v_banding;
flat in ivec4 v_glyph;
flat in vec2 v_effect;   // Dilation px, filter width px.

layout(location = 0) out vec4 o_color;

const int kLogBandTextureWidth = 12;

// Root eligibility from the signs of the sample-relative control point coordinates.
// Bit 0 enables the first root, bit 8 the second.
uint slug_root_code(float y1, float y2, float y3)
{
    uint i1 = floatBitsToUint(y1) >> 31u;
    uint i2 = floatBitsToUint(y2) >> 30u;
    uint i3 = floatBitsToUint(y3) >> 29u;

    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);
    return (0x2E74u >> shift) & 0x0101u;
}

// x coordinates where the curve crosses y = 0. Imaginary roots collapse to the extremum.
vec2 slug_solve_horiz(vec4 p12, vec2 p3)
{
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
    float ra = 1.0 / a.y;
    float rb = 0.5 / b.y;

    float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    float t1 = (b.y - d) * ra;
    float t2 = (b.y + d) * ra;

    if (abs(a.y) < 1.0 / 65536.0) t1 = t2 = p12.y * rb;

    return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x, (a.x * t2 - b.x * 2.0) * t2 + p12.x);
}

// y coordinates where the curve crosses x = 0.
vec2 slug_solve_vert(vec4 p12, vec2 p3)
{
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
    float ra = 1.0 / a.x;
    float rb = 0.5 / b.x;

    float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
    float t1 = (b.x - d) * ra;
    float t2 = (b.x + d) * ra;

    if (abs(a.x) < 1.0 / 65536.0) t1 = t2 = p12.x * rb;

    return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y, (a.y * t2 - b.y * 2.0) * t2 + p12.y);
}

// Offsets past the end of a row wrap to the next row.
ivec2 slug_band_loc(ivec2 glyph_loc, uint offset)
{
    ivec2 band_loc = ivec2(glyph_loc.x + int(offset), glyph_loc.y);
    band_loc.y += band_loc.x >> kLogBandTextureWidth;
    band_loc.x &= (1 << kLogBandTextureWidth) - 1;
    return band_loc;
}

// Away from edges both rays must agree (min).
float slug_coverage(float xcov, float ycov, float xwgt, float ywgt, int flags)
{
    float agreed = min(abs(xcov), abs(ycov));
    float coverage = max(abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0), agreed);

    if ((flags & 0x1000) == 0)
        coverage = clamp(coverage, 0.0, 1.0);                         // nonzero
    else
        coverage = 1.0 - abs(1.0 - fract(coverage * 0.5) * 2.0);      // even-odd

    if ((flags & 0x2000) != 0) coverage = sqrt(coverage);              // optical weight

    return coverage;
}

// Reference coverage of the sample at render_coord: each root r (in pixels along the ray)
// contributes clamp(r + 0.5), a one-pixel box filter. Effects run in slug_render_soft and
// slug_render_offset (SLUG_EFFECTS variant).
float slug_render(vec2 render_coord, vec2 pixels_per_em, vec4 band_transform, ivec4 glyph_data)
{
    int band_max_x = glyph_data.z;
    int band_max_y = glyph_data.w & 0x00FF;
    ivec2 band_max = ivec2(band_max_x, band_max_y);

    ivec2 band_index = clamp(ivec2(render_coord * band_transform.xy + band_transform.zw), ivec2(0, 0), band_max);
    ivec2 glyph_loc = glyph_data.xy;

    float xcov = 0.0;
    float xwgt = 0.0;

    uvec2 hband_data = texelFetch(slug_band, ivec2(glyph_loc.x + band_index.y, glyph_loc.y), 0).xy;
    ivec2 hband_loc = slug_band_loc(glyph_loc, hband_data.y);

    for (int curve_index = 0; curve_index < int(hband_data.x); curve_index++) {
        ivec2 curve_loc = ivec2(texelFetch(slug_band, ivec2(hband_loc.x + curve_index, hband_loc.y), 0).xy);

        vec4 p12 = texelFetch(slug_curve, curve_loc, 0) - vec4(render_coord, render_coord);
        vec2 p3 = texelFetch(slug_curve, ivec2(curve_loc.x + 1, curve_loc.y), 0).xy - render_coord;

        // Curves are sorted by descending max x; the rest lie left of the pixel.
        if (max(max(p12.x, p12.z), p3.x) * pixels_per_em.x < -0.5) break;

        uint code = slug_root_code(p12.y, p12.w, p3.y);
        if (code != 0u) {
            vec2 r = slug_solve_horiz(p12, p3) * pixels_per_em.x;

            if ((code & 1u) != 0u) {
                xcov += clamp(r.x + 0.5, 0.0, 1.0);
                xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
            }
            if (code > 1u) {
                xcov -= clamp(r.y + 0.5, 0.0, 1.0);
                xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
            }
        }
    }

    float ycov = 0.0;
    float ywgt = 0.0;

    uvec2 vband_data = texelFetch(slug_band, ivec2(glyph_loc.x + band_max.y + 1 + band_index.x, glyph_loc.y), 0).xy;
    ivec2 vband_loc = slug_band_loc(glyph_loc, vband_data.y);

    for (int curve_index = 0; curve_index < int(vband_data.x); curve_index++) {
        ivec2 curve_loc = ivec2(texelFetch(slug_band, ivec2(vband_loc.x + curve_index, vband_loc.y), 0).xy);

        vec4 p12 = texelFetch(slug_curve, curve_loc, 0) - vec4(render_coord, render_coord);
        vec2 p3 = texelFetch(slug_curve, ivec2(curve_loc.x + 1, curve_loc.y), 0).xy - render_coord;

        // Curves are sorted by descending max y; the rest lie below the pixel.
        if (max(max(p12.y, p12.w), p3.y) * pixels_per_em.y < -0.5) break;

        uint code = slug_root_code(p12.x, p12.z, p3.x);
        if (code != 0u) {
            vec2 r = slug_solve_vert(p12, p3) * pixels_per_em.y;

            if ((code & 1u) != 0u) {
                ycov -= clamp(r.x + 0.5, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
            }
            if (code > 1u) {
                ycov += clamp(r.y + 0.5, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
            }
        }
    }

    return slug_coverage(xcov, ycov, xwgt, ywgt, glyph_data.w);
}

#ifdef SLUG_EFFECTS
// Effects variant only (shaders/effects.glsl defines SLUG_EFFECTS): backends draw with it when an
// instance has dilation or softness, so this code never costs registers in the plain shader.

// Fill of a winding number: 1 inside, 0 outside (nonzero or even-odd rule).
float slug_fill(float winding, bool even_odd)
{
    return even_odd ? mod(abs(winding), 2.0) : min(abs(winding), 1.0);
}

// Nearest point of the quadratic Bezier (p0, p1, p2) to the origin, in pixels. The closest t solves t^3 + 3 kx t^2 + 3 ky t + kz = 0 (Cardano; with
// three real roots the trigonometric form, whose middle root is never the minimum).
struct SlugNearest {
    float distance2;
    vec2 point;
};

SlugNearest slug_quad_nearest(vec2 p0, vec2 p1, vec2 p2)
{
    vec2 a = p1 - p0;
    vec2 b = p0 - 2.0 * p1 + p2;
    vec2 c = a * 2.0;
    vec2 e = p2 - p0;
    float t;
    vec2 point;
    // Collinear control points (lines are stored with a doubled end point): the segment p0 p2.
    if (abs(a.x * e.y - a.y * e.x) <= 1.0e-5 * (dot(a, a) + dot(e, e))) {
        t = clamp(-dot(p0, e) / max(dot(e, e), 1.0e-20), 0.0, 1.0);
        point = p0 + e * t;
    } else {
        float kk = 1.0 / dot(b, b);
        float kx = kk * dot(a, b);
        float ky = kk * (2.0 * dot(a, a) + dot(p0, b)) / 3.0;
        float kz = kk * dot(p0, a);
        float p = ky - kx * kx;
        float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
        float h = q * q + 4.0 * p * p * p;
        if (h >= 0.0) {
            h = sqrt(h);
            vec2 x = (vec2(h, -h) - q) * 0.5;
            vec2 uv = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
            t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        } else {
            float z = sqrt(-p);
            float v = acos(q / (p * z * 2.0)) / 3.0;
            float m = cos(v);
            float n = sin(v) * 1.732050808;
            vec2 ts = clamp(vec2(m + m, -n - m) * z - kx, 0.0, 1.0);
            vec2 r0 = p0 + (c + b * ts.x) * ts.x;
            vec2 r1 = p0 + (c + b * ts.y) * ts.y;
            t = dot(r0, r0) <= dot(r1, r1) ? ts.x : ts.y;
        }
        point = p0 + (c + b * t) * t;
    }
    return SlugNearest(dot(point, point), point);
}

// Winding number at coord from the horizontal ray of its band (crossings to the right).
float slug_winding(vec2 coord, vec4 band_transform, ivec4 glyph_data)
{
    int band = clamp(int(coord.y * band_transform.y + band_transform.w), 0, glyph_data.w & 0x00FF);
    uvec2 band_data = texelFetch(slug_band, ivec2(glyph_data.x + band, glyph_data.y), 0).xy;
    ivec2 band_loc = slug_band_loc(glyph_data.xy, band_data.y);
    float winding = 0.0;
    for (int curve_index = 0; curve_index < int(band_data.x); curve_index++) {
        ivec2 curve_loc = ivec2(texelFetch(slug_band, ivec2(band_loc.x + curve_index, band_loc.y), 0).xy);
        vec4 p12 = texelFetch(slug_curve, curve_loc, 0) - vec4(coord, coord);
        vec2 p3 = texelFetch(slug_curve, ivec2(curve_loc.x + 1, curve_loc.y), 0).xy - coord;
        if (max(max(p12.x, p12.z), p3.x) < 0.0) break;   // the rest cannot cross the ray to the right
        uint code = slug_root_code(p12.y, p12.w, p3.y);
        if (code != 0u) {
            vec2 r = slug_solve_horiz(p12, p3);
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
bool slug_on_boundary(SlugNearest nearest, bool inside, bool even_odd, vec2 render_coord, vec2 pixels_per_em,
                      vec4 band_transform, ivec4 glyph_data)
{
    if (!inside) return true;
    vec2 probe = nearest.point * (1.0 + 0.25 / max(sqrt(nearest.distance2), 1.0e-6));
    return slug_fill(slug_winding(render_coord + probe / pixels_per_em, band_transform, glyph_data), even_odd) == 0.0;
}

// Squared pixel distance to the nearest curve within reach (reach^2 when none). With `checked` (the
// sample is inside), only boundary curves count (slug_on_boundary). Curves within reach can lie in
// neighboring bands, so all horizontal bands within reach are searched; horizontal lines, which
// horizontal bands leave out, come from the sample's own vertical band.
float slug_nearest_curve2(vec2 render_coord, vec2 pixels_per_em, vec4 band_transform, ivec4 glyph_data, float reach,
                          bool checked)
{
    ivec2 band_max = ivec2(glyph_data.z, glyph_data.w & 0x00FF);
    ivec2 glyph_loc = glyph_data.xy;
    bool even_odd = (glyph_data.w & 0x1000) != 0;
    float reach_em = reach / pixels_per_em.y;
    int lo = clamp(int((render_coord.y - reach_em) * band_transform.y + band_transform.w), 0, band_max.y);
    int hi = clamp(int((render_coord.y + reach_em) * band_transform.y + band_transform.w), 0, band_max.y);

    float best = reach * reach;
    for (int band = lo; band <= hi; band++) {
        uvec2 band_data = texelFetch(slug_band, ivec2(glyph_loc.x + band, glyph_loc.y), 0).xy;
        ivec2 band_loc = slug_band_loc(glyph_loc, band_data.y);

        for (int curve_index = 0; curve_index < int(band_data.x); curve_index++) {
            ivec2 curve_loc = ivec2(texelFetch(slug_band, ivec2(band_loc.x + curve_index, band_loc.y), 0).xy);
            vec4 p12 = texelFetch(slug_curve, curve_loc, 0) - vec4(render_coord, render_coord);
            vec2 p3 = texelFetch(slug_curve, ivec2(curve_loc.x + 1, curve_loc.y), 0).xy - render_coord;
            vec4 q12 = p12 * pixels_per_em.xyxy;
            vec2 q3 = p3 * pixels_per_em;

            // Sorted by descending max x: the rest lie further left than the reach.
            if (max(max(q12.x, q12.z), q3.x) < -reach) break;

            vec2 gap = max(max(min(min(q12.xy, q12.zw), q3), -max(max(q12.xy, q12.zw), q3)), 0.0);
            if (dot(gap, gap) >= best) continue;
            SlugNearest nearest = slug_quad_nearest(q12.xy, q12.zw, q3);
            if (nearest.distance2 < best
                && (!checked || slug_on_boundary(nearest, true, even_odd, render_coord, pixels_per_em, band_transform,
                                                 glyph_data)))
                best = nearest.distance2;
        }
    }

    // Horizontal lines: where the sample lies within a line's x span, the vertical gap is the distance;
    // elsewhere the nearest point is a line end, shared with a neighboring curve found above. Lines
    // spanning the sample's x are all in its own vertical band.
    int column = clamp(int(render_coord.x * band_transform.x + band_transform.z), 0, band_max.x);
    uvec2 column_data = texelFetch(slug_band, ivec2(glyph_loc.x + band_max.y + 1 + column, glyph_loc.y), 0).xy;
    ivec2 column_loc = slug_band_loc(glyph_loc, column_data.y);
    for (int curve_index = 0; curve_index < int(column_data.x); curve_index++) {
        ivec2 curve_loc = ivec2(texelFetch(slug_band, ivec2(column_loc.x + curve_index, column_loc.y), 0).xy);
        vec4 p12 = texelFetch(slug_curve, curve_loc, 0) - vec4(render_coord, render_coord);
        vec2 p3 = texelFetch(slug_curve, ivec2(curve_loc.x + 1, curve_loc.y), 0).xy - render_coord;

        // Sorted by descending max y: the rest lie further below than the reach.
        if (max(max(p12.y, p12.w), p3.y) * pixels_per_em.y < -reach) break;
        if (p12.y != p12.w || p12.y != p3.y || min(p12.x, p3.x) > 0.0 || max(p12.x, p3.x) < 0.0) continue;

        float gap = p12.y * pixels_per_em.y;
        if (gap * gap < best
            && (!checked || slug_on_boundary(SlugNearest(gap * gap, vec2(0.0, gap)), true, even_odd, render_coord,
                                             pixels_per_em, band_transform, glyph_data)))
            best = gap * gap;
    }
    return best;
}

// Thinning, and growth of a pixel or more, without softness: the outline offset by `dilation` pixels
// in every direction, so corners
// grow round and thinning removes exactly the strip along the edges. Coverage is
// clamp(0.5 + dilation - s), s the signed distance in pixels to the nearest boundary curve (negative
// inside). The winding comes first and ends the work where no edge can reach (inside when growing by
// half a pixel or more, outside when thinning by that much). Outside the fill every curve bounds it;
// inside, hidden curves must be skipped at the cost of a winding probe per candidate, so the checked
// search runs only where an edge can matter.
float slug_render_offset(vec2 render_coord, vec2 pixels_per_em, vec4 band_transform, ivec4 glyph_data,
                         float dilation)
{
    bool even_odd = (glyph_data.w & 0x1000) != 0;
    float reach = abs(dilation) + 0.5;
    bool inside = slug_fill(slug_winding(render_coord, band_transform, glyph_data), even_odd) != 0.0;
    if (inside ? dilation >= 0.5 : dilation <= -0.5) return inside ? 1.0 : 0.0;

    float distance2 = slug_nearest_curve2(render_coord, pixels_per_em, band_transform, glyph_data, reach, false);
    if (inside && (dilation > 0.0 ? sqrt(distance2) >= 0.5 - dilation : distance2 >= reach * reach)) return 1.0;
    if (inside)
        distance2 = slug_nearest_curve2(render_coord, pixels_per_em, band_transform, glyph_data, reach, true);

    float distance = sqrt(distance2);
    float coverage = clamp(0.5 + dilation - (inside ? -distance : distance), 0.0, 1.0);
    if ((glyph_data.w & 0x2000) != 0) coverage = sqrt(coverage);
    return coverage;
}

const int kSoftRoots = 8;   // window roots kept per soft ray; with more the ray falls back to winding averaging
const int kSoftRays = 16;   // sample rays per axis at most

// One ray of the soft path (vertical rays run on swapped coordinates): the fill of the winding
// number integrated over the filter window [-0.5, 0.5] (in filter widths), so overlapping contours
// count once. Roots past the window add to the base winding; roots inside are kept sorted. average
// is the winding averaged over the window (slug_render's per-ray sum), used when roots overflow.
float slug_soft_ray(vec2 coord, float ppe, vec4 band_transform, ivec4 glyph_data, bool vertical, float shift,
                    float inv_filter, float reach)
{
    ivec2 band_max = ivec2(glyph_data.z, glyph_data.w & 0x00FF);
    ivec2 band_index = clamp(ivec2(coord * band_transform.xy + band_transform.zw), ivec2(0, 0), band_max);
    ivec2 glyph_loc = glyph_data.xy;
    int header = vertical ? band_max.y + 1 + band_index.x : band_index.y;
    uvec2 band_data = texelFetch(slug_band, ivec2(glyph_loc.x + header, glyph_loc.y), 0).xy;
    ivec2 band_loc = slug_band_loc(glyph_loc, band_data.y);
    float sgn = vertical ? -1.0 : 1.0;

    float roots[kSoftRoots];
    float signs[kSoftRoots];
    int count = 0;
    float winding = 0.0;
    float average = 0.0;

    for (int curve_index = 0; curve_index < int(band_data.x); curve_index++) {
        ivec2 curve_loc = ivec2(texelFetch(slug_band, ivec2(band_loc.x + curve_index, band_loc.y), 0).xy);

        vec4 p12 = texelFetch(slug_curve, curve_loc, 0) - vec4(coord, coord);
        vec2 p3 = texelFetch(slug_curve, ivec2(curve_loc.x + 1, curve_loc.y), 0).xy - coord;
        if (vertical) {
            p12 = p12.yxwz;
            p3 = p3.yx;
        }

        if (max(max(p12.x, p12.z), p3.x) * ppe < reach) break;

        uint code = slug_root_code(p12.y, p12.w, p3.y);
        if (code == 0u) continue;
        vec2 r = (slug_solve_horiz(p12, p3) * ppe + vec2(-shift, shift) * sgn) * inv_filter;

        for (int k = 0; k < 2; k++) {
            if (k == 0 ? (code & 1u) == 0u : code <= 1u) continue;
            float u = k == 0 ? r.x : r.y;
            float s = k == 0 ? sgn : -sgn;
            average += s * clamp(u + 0.5, 0.0, 1.0);
            if (u >= 0.5) {
                winding += s;
            } else if (u > -0.5) {
                if (count < kSoftRoots) {
                    int j = count++;
                    while (j > 0 && roots[j - 1] < u) {
                        roots[j] = roots[j - 1];
                        signs[j] = signs[j - 1];
                        j--;
                    }
                    roots[j] = u;
                    signs[j] = s;
                } else {
                    count = kSoftRoots + 1;
                }
            }
        }
    }

    bool even_odd = (glyph_data.w & 0x1000) != 0;
    if (count > kSoftRoots) return even_odd ? 1.0 - abs(1.0 - fract(average * 0.5) * 2.0) : clamp(abs(average), 0.0, 1.0);

    // The winding left of a root includes it; integrate from the right end of the window.
    float covered = 0.0;
    float upper = 0.5;
    for (int k = 0; k < count; k++) {
        covered += (upper - roots[k]) * slug_fill(winding, even_odd);
        winding += signs[k];
        upper = roots[k];
    }
    covered += (upper + 0.5) * slug_fill(winding, even_odd);
    return covered;
}

// Soft coverage (filter width > 1): a filter_width^2 box around the sample. Horizontal rays at evenly
// spaced rows integrate x exactly, vertical rays at evenly spaced columns integrate y; the two
// estimates are averaged, or combined with max (dilation > 0) / min (dilation < 0). Under softness,
// dilation shifts roots along each ray (not the Euclidean offset of slug_render_offset).
// Each estimate is within 0.5 / rays of the exact box filter.
float slug_render_soft(vec2 render_coord, vec2 pixels_per_em, vec4 band_transform, ivec4 glyph_data,
                       float dilation, float filter_width)
{
    float shift = (glyph_data.w & 0x8000) != 0 ? dilation : -dilation;
    float inv_filter = 1.0 / filter_width;
    float reach = -0.5 * filter_width - abs(dilation);
    // spacing up to 2 px; at least 3 rays keeps width 2 off the pixel grid (offsets of +-0.5 px)
    int rays = min(max(int(ceil(filter_width * 0.5)) + 1, 3), kSoftRays);

    float across = 0.0;
    float down = 0.0;
    for (int i = 0; i < rays; i++) {
        float offset = ((float(i) + 0.5) / float(rays) - 0.5) * filter_width;
        across += slug_soft_ray(render_coord + vec2(0.0, offset / pixels_per_em.y), pixels_per_em.x, band_transform,
                                glyph_data, false, shift, inv_filter, reach);
        down += slug_soft_ray(render_coord + vec2(offset / pixels_per_em.x, 0.0), pixels_per_em.y, band_transform,
                              glyph_data, true, shift, inv_filter, reach);
    }
    across /= float(rays);
    down /= float(rays);

    float coverage = dilation > 0.0 ? max(across, down) : dilation < 0.0 ? min(across, down) : 0.5 * (across + down);
    if ((glyph_data.w & 0x2000) != 0) coverage = sqrt(coverage);
    return coverage;
}

// One ray of slug_render_shift (vertical rays run on swapped coordinates): roots shifted outward by
// `shift` pixels, each contributing clamp(r + 0.5) with its sign, as in slug_render.
float slug_shift_ray(vec2 coord, float ppe, vec4 band_transform, ivec4 glyph_data, bool vertical, float shift,
                     float reach)
{
    ivec2 band_max = ivec2(glyph_data.z, glyph_data.w & 0x00FF);
    ivec2 band_index = clamp(ivec2(coord * band_transform.xy + band_transform.zw), ivec2(0, 0), band_max);
    ivec2 glyph_loc = glyph_data.xy;
    int header = vertical ? band_max.y + 1 + band_index.x : band_index.y;
    uvec2 band_data = texelFetch(slug_band, ivec2(glyph_loc.x + header, glyph_loc.y), 0).xy;
    ivec2 band_loc = slug_band_loc(glyph_loc, band_data.y);
    float sgn = vertical ? -1.0 : 1.0;

    float coverage = 0.0;
    for (int curve_index = 0; curve_index < int(band_data.x); curve_index++) {
        ivec2 curve_loc = ivec2(texelFetch(slug_band, ivec2(band_loc.x + curve_index, band_loc.y), 0).xy);
        vec4 p12 = texelFetch(slug_curve, curve_loc, 0) - vec4(coord, coord);
        vec2 p3 = texelFetch(slug_curve, ivec2(curve_loc.x + 1, curve_loc.y), 0).xy - coord;
        if (vertical) {
            p12 = p12.yxwz;
            p3 = p3.yx;
        }
        if (max(max(p12.x, p12.z), p3.x) * ppe < reach) break;

        uint code = slug_root_code(p12.y, p12.w, p3.y);
        if (code == 0u) continue;
        vec2 r = slug_solve_horiz(p12, p3) * ppe + vec2(-shift, shift) * sgn;
        if ((code & 1u) != 0u) coverage += sgn * clamp(r.x + 0.5, 0.0, 1.0);
        if (code > 1u) coverage -= sgn * clamp(r.y + 0.5, 0.0, 1.0);
    }
    return coverage;
}

// Growth below one pixel (bold): edges shift outward along the horizontal and vertical ray, and either
// ray's span counts (max). Shifted outward, intervals only widen, so the winding sums stay valid with
// overlapping contours. Corners differ from the true offset of slug_render_offset by under a third of
// a pixel, at a fraction of its cost. Thinning always takes slug_render_offset: shifted inward, the two
// copies of an edge shared by touching contours would open a gap.
float slug_render_shift(vec2 render_coord, vec2 pixels_per_em, vec4 band_transform, ivec4 glyph_data, float dilation)
{
    float shift = (glyph_data.w & 0x8000) != 0 ? dilation : -dilation;
    float reach = -0.5 - dilation;
    float across = slug_shift_ray(render_coord, pixels_per_em.x, band_transform, glyph_data, false, shift, reach);
    float down = slug_shift_ray(render_coord, pixels_per_em.y, band_transform, glyph_data, true, shift, reach);
    float coverage = max(abs(across), abs(down));
    if ((glyph_data.w & 0x1000) == 0)
        coverage = clamp(coverage, 0.0, 1.0);
    else
        coverage = 1.0 - abs(1.0 - fract(coverage * 0.5) * 2.0);
    if ((glyph_data.w & 0x2000) != 0) coverage = sqrt(coverage);
    return coverage;
}
#endif

void main()
{
    vec2 dx = dFdx(v_texcoord);
    vec2 dy = dFdy(v_texcoord);
    vec2 pixels_per_em = 1.0 / (abs(dx) + abs(dy));

#ifdef SLUG_EFFECTS
    float coverage = v_effect.y > 1.0        ? slug_render_soft(v_texcoord, pixels_per_em, v_banding, v_glyph, v_effect.x, v_effect.y)
                     : v_effect.x > 0.0 && v_effect.x < 1.0 ? slug_render_shift(v_texcoord, pixels_per_em, v_banding, v_glyph, v_effect.x)
                     : v_effect.x != 0.0      ? slug_render_offset(v_texcoord, pixels_per_em, v_banding, v_glyph, v_effect.x)
                                              : slug_render(v_texcoord, pixels_per_em, v_banding, v_glyph);
#else
    float coverage = slug_render(v_texcoord, pixels_per_em, v_banding, v_glyph);
#endif
    o_color = v_color * coverage;
}
