# src/slug/outline.cr
require "./half"
require "./lib_ft"
require "./error"
require "./types"
require "./font"

module Slug
  # :nodoc:
  struct Vec2
    getter x : Float32
    getter y : Float32

    def initialize(@x : Float32, @y : Float32)
    end

    def self.zero : Vec2
      new 0.0_f32, 0.0_f32
    end
  end

  # :nodoc:
  #
  # One quadratic curve with half-quantized em-space control points.
  struct Curve
    getter p : StaticArray(Vec2, 3)

    def initialize(@p : StaticArray(Vec2, 3))
    end
  end

  # :nodoc:
  #
  # Glyph outline as a texel chain, copied from FreeType by `capture` or from
  # a `Path` by `from_path` and decomposed by `build`. Each contour stores
  # n + 1 texels for n curves: texel i = (start_i, control_i), the last =
  # (end, 0). Curve i reads texels `curve_texel[i]` and `curve_texel[i] + 1`.
  class Outline
    CUBIC_MAX_DEPTH = 16

    getter texels = [] of StaticArray(UInt16, 4)
    getter curves = [] of Curve
    getter curve_texel = [] of UInt32
    getter bounds : StaticArray(Float32, 4)
    getter advance = 0.0_f32
    getter scale = 0.0_f32
    getter? even_odd = false
    getter? reversed = false

    # FreeType outline copied by `capture` / `from_path`.
    getter points = [] of LibFT::Vector
    getter tags = [] of UInt8
    getter contours = [] of UInt16
    getter n_points = 0
    getter n_contours = 0
    getter source_flags = 0

    # Current contour during `build`, unquantized.
    getter seg_ctrl = [] of Vec2
    getter seg_end = [] of Vec2

    def initialize
      @bounds = StaticArray[Float32::INFINITY, Float32::INFINITY, -Float32::INFINITY, -Float32::INFINITY]
    end

    # Loads a glyph with FreeType (serial per face) and copies its outline,
    # advance and fill rule.
    def capture(font : Font, glyph_id : UInt32) : Result
      face = font.face
      @n_points = 0
      @n_contours = 0

      style = font.outline_style
      flags = LibFT::LOAD_NO_BITMAP | LibFT::LOAD_NO_SVG
      scale : Float32
      if style.hinting.none?
        flags |= LibFT::LOAD_NO_SCALE | LibFT::LOAD_NO_HINTING
        scale = 1.0_f32 / face.value.units_per_em.to_f32
      else
        flags |= style.hinting.light? ? LibFT::LOAD_TARGET_LIGHT : LibFT::LOAD_TARGET_NORMAL
        flags |= LibFT::LOAD_FORCE_AUTOHINT if style.autohint?
        scale = 1.0_f32 / (style.pixels_per_em * 64.0_f32)
      end
      return Result::FreeType unless LibFT.FT_Load_Glyph(face, glyph_id, flags) == 0

      @scale = scale
      slot = face.value.glyph
      @advance = slot.value.metrics.hori_advance.to_f32 * scale
      return Result::Unsupported unless slot.value.format == LibFT::GLYPH_FORMAT_OUTLINE

      src = slot.value.outline
      if style.embolden > 0.0_f32
        strength = (style.embolden / scale).round(mode: :ties_away).to_i64
        return Result::FreeType unless LibFT.FT_Outline_EmboldenXY(pointerof(src), strength, strength) == 0
      end

      points = src.n_points.to_i
      contours = src.n_contours.to_i
      @points.clear
      @tags.clear
      @contours.clear
      points.times do |i|
        @points << src.points[i]
        @tags << src.tags[i]
      end
      contours.times { |i| @contours << src.contours[i] }
      @n_points = points
      @n_contours = contours
      @source_flags = src.flags
      @even_odd = (src.flags & LibFT::OUTLINE_EVEN_ODD_FILL) != 0
      Result::Ok
    end

    # Turns the captured outline into quantized texel chains. Pure
    # computation: safe on any thread.
    def build(cubic_tolerance : Float32) : Result
      @texels.clear
      @curves.clear
      @curve_texel.clear
      @seg_ctrl.clear
      @seg_end.clear
      @bounds = StaticArray[Float32::INFINITY, Float32::INFINITY, -Float32::INFINITY, -Float32::INFINITY]

      builder = Builder.new(self, @scale, cubic_tolerance)
      funcs = LibFT::OutlineFuncs.new
      funcs.move_to = ->(to : LibFT::Vector*, user : Void*) : LibFT::Int { Box(Builder).unbox(user).move(to) }
      funcs.line_to = ->(to : LibFT::Vector*, user : Void*) : LibFT::Int { Box(Builder).unbox(user).line(to) }
      funcs.conic_to = ->(ctrl : LibFT::Vector*, to : LibFT::Vector*, user : Void*) : LibFT::Int { Box(Builder).unbox(user).conic(ctrl, to) }
      funcs.cubic_to = ->(c1 : LibFT::Vector*, c2 : LibFT::Vector*, to : LibFT::Vector*, user : Void*) : LibFT::Int { Box(Builder).unbox(user).cubic(c1, c2, to) }
      funcs.shift = 0
      funcs.delta = 0_i64

      source = LibFT::Outline.new
      source.n_contours = @n_contours.to_u16
      source.n_points = @n_points.to_u16
      source.points = @points.to_unsafe
      source.tags = @tags.to_unsafe
      source.contours = @contours.to_unsafe
      source.flags = @source_flags

      return Result::FreeType unless LibFT.FT_Outline_Decompose(pointerof(source), pointerof(funcs), Box.box(builder)) == 0
      builder.flush_contour

      # Signed area of the control polygons: positive = counter-clockwise outer contours.
      area = 0.0_f64
      @curves.each do |curve|
        p = curve.p
        area += (p[0].x * p[1].y - p[1].x * p[0].y).to_f64 +
                (p[1].x * p[2].y - p[2].x * p[1].y).to_f64
      end
      @reversed = area > 0.0
      Result::Ok
    end

    # Copies *path* into the source outline, normalized to the unit square
    # (see `Shape`), and returns the result with the path coordinates of the
    # normalized origin (path bounds minimum) and the path units per
    # normalized unit. Expects the `Path` :nodoc: storage mirroring the C
    # SlugPath: `point_count`/`contour_count`, flat `xy` pairs, FreeType `tags`
    # bytes and contour `ends` indices.
    def from_path(path : Path, fill : FillRule) : {Result, StaticArray(Float32, 2), Float32}
      origin = StaticArray[0.0_f32, 0.0_f32]
      scale = 1.0_f32
      @n_points = 0
      @n_contours = 0
      @advance = 0.0_f32
      @scale = 1.0_f32 / 65536.0_f32

      points = path.point_count
      contours = path.contour_count
      return {Result::Unsupported, origin, scale} if points == 0 || contours == 0
      return {Result::Limit, origin, scale} if points > 65535 || contours > 65535

      xy = path.xy
      lo_x = Float32::INFINITY
      lo_y = Float32::INFINITY
      hi_x = -Float32::INFINITY
      hi_y = -Float32::INFINITY
      points.times do |i|
        x = xy[2 * i]
        y = xy[2 * i + 1]
        lo_x = minf(lo_x, x)
        lo_y = minf(lo_y, y)
        hi_x = maxf(hi_x, x)
        hi_y = maxf(hi_y, y)
      end
      extent = maxf(hi_x - lo_x, hi_y - lo_y)
      return {Result::Unsupported, origin, scale} unless extent > 0.0_f32 && extent.finite?

      tags = path.tags
      ends = path.ends
      @points.clear
      @tags.clear
      @contours.clear

      # Normalized coordinates in 16.16 fixed point, decomposed with scale 1/65536.
      inv = 65536.0_f32 / extent
      points.times do |i|
        v = LibFT::Vector.new
        v.x = ((xy[2 * i] - lo_x) * inv).round(mode: :ties_away).to_i64
        v.y = ((xy[2 * i + 1] - lo_y) * inv).round(mode: :ties_away).to_i64
        @points << v
        @tags << tags[i].to_u8
      end
      contours.times { |c| @contours << ends[c].to_u16 }
      @n_points = points
      @n_contours = contours
      @source_flags = fill.even_odd? ? LibFT::OUTLINE_EVEN_ODD_FILL : 0
      @even_odd = fill.even_odd?
      origin = StaticArray[lo_x, lo_y]
      {Result::Ok, origin, extent}
    end

    # Appends the half-quantized (a, b) texel.
    def push_texel(a : Vec2, b : Vec2) : Nil
      @texels << StaticArray[Half.from_float(a.x), Half.from_float(a.y), Half.from_float(b.x), Half.from_float(b.y)]
      nil
    end

    def grow_bounds(p : Vec2) : Nil
      b = @bounds
      @bounds = StaticArray[minf(b[0], p.x), minf(b[1], p.y), maxf(b[2], p.x), maxf(b[3], p.y)]
      nil
    end

    # fminf/fmaxf: a NaN operand is ignored.
    private def minf(a : Float32, b : Float32) : Float32
      return b if a.nan?
      return a if b.nan?
      a < b ? a : b
    end

    private def maxf(a : Float32, b : Float32) : Float32
      return b if a.nan?
      return a if b.nan?
      a > b ? a : b
    end

    private class Builder
      @start = Vec2.zero
      @cursor = Vec2.zero

      def initialize(@out : Outline, @scale : Float32, @tolerance : Float32)
      end

      def move(to : LibFT::Vector*) : LibFT::Int
        flush_contour
        @start = @cursor = to_em(to)
        0
      end

      def line(to : LibFT::Vector*) : LibFT::Int
        end_pt = to_em(to)
        push_segment(end_pt, end_pt)
      end

      def conic(ctrl : LibFT::Vector*, to : LibFT::Vector*) : LibFT::Int
        push_segment(to_em(ctrl), to_em(to))
      end

      def cubic(c1 : LibFT::Vector*, c2 : LibFT::Vector*, to : LibFT::Vector*) : LibFT::Int
        push_cubic(@cursor, to_em(c1), to_em(c2), to_em(to), 0)
      end

      # Quantizes the pending contour, drops degenerate curves and appends its texel chain.
      def flush_contour : Nil
        o = @out
        n = o.seg_ctrl.size
        return if n == 0

        start = quantize(@start)
        kept = 0
        chain_base = o.texels.size
        n.times do |i|
          ctrl = quantize(o.seg_ctrl[i])
          end_pt = quantize(o.seg_end[i])
          next if same?(start, ctrl) && same?(ctrl, end_pt)

          o.push_texel(start, ctrl)
          o.curves << Curve.new(StaticArray[start, ctrl, end_pt])
          o.curve_texel << (chain_base + kept).to_u32
          kept += 1
          o.grow_bounds(start)
          o.grow_bounds(ctrl)
          o.grow_bounds(end_pt)
          start = end_pt
        end
        o.push_texel(start, Vec2.zero) if kept > 0
        o.seg_ctrl.clear
        o.seg_end.clear
        nil
      end

      private def to_em(v : LibFT::Vector*) : Vec2
        Vec2.new(v.value.x.to_f32 * @scale, v.value.y.to_f32 * @scale)
      end

      private def quantize(v : Vec2) : Vec2
        Vec2.new(Half.to_float(Half.from_float(v.x)), Half.to_float(Half.from_float(v.y)))
      end

      private def same?(a : Vec2, b : Vec2) : Bool
        a.x == b.x && a.y == b.y
      end

      private def mid(a : Vec2, b : Vec2) : Vec2
        Vec2.new((a.x + b.x) * 0.5_f32, (a.y + b.y) * 0.5_f32)
      end

      private def push_segment(ctrl : Vec2, end_pt : Vec2) : LibFT::Int
        @out.seg_ctrl << ctrl
        @out.seg_end << end_pt
        @cursor = end_pt
        0
      end

      # Approximates a cubic by quadratics within the tolerance (midpoint degree reduction).
      private def push_cubic(p0 : Vec2, c1 : Vec2, c2 : Vec2, p3 : Vec2, depth : Int32) : LibFT::Int
        dx = p3.x - 3.0_f32 * c2.x + 3.0_f32 * c1.x - p0.x
        dy = p3.y - 3.0_f32 * c2.y + 3.0_f32 * c1.y - p0.y
        error = Math.sqrt(dx * dx + dy * dy) * (1.7320508_f32 / 36.0_f32)

        if error <= @tolerance || depth >= CUBIC_MAX_DEPTH
          q = Vec2.new(
            (3.0_f32 * (c1.x + c2.x) - p0.x - p3.x) * 0.25_f32,
            (3.0_f32 * (c1.y + c2.y) - p0.y - p3.y) * 0.25_f32)
          return push_segment(q, p3)
        end

        m01 = mid(p0, c1)
        m12 = mid(c1, c2)
        m23 = mid(c2, p3)
        a = mid(m01, m12)
        c = mid(m12, m23)
        m = mid(a, c)
        push_cubic(p0, m01, a, m, depth + 1)
        push_cubic(m, c, m23, p3, depth + 1)
      end
    end
  end
end
