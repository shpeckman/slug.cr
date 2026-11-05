# src/slug/path.cr

require "./error"

module Slug
  # A vector path under construction: a contour builder in FreeType
  # point/tag form (on-curve, conic and cubic control points).
  #
  # Contours close implicitly: every `#move_to` starts a new contour, and a
  # contour's last point connects back to its first. A contour holding only
  # its `#move_to` point is replaced by the next `#move_to`. Coordinates are
  # in arbitrary units (e.g. an icon's 24x24 grid), y up.
  class Path
    # :nodoc: kind of a path point, the FT_CURVE_TAG_* values
    enum PointTag : UInt8
      Conic = 0
      On    = 1
      Cubic = 2
    end

    @xy = [] of Float32
    @tags = [] of PointTag
    @ends = [] of UInt32
    @open = false

    # Removes all contours, keeping the storage.
    def reset : Nil
      @xy.clear
      @tags.clear
      @ends.clear
      @open = false
    end

    # Starts a new contour at (*x*, *y*) and returns self.
    #
    # Raises `Error` when a coordinate is not finite.
    def move_to(x : Float32, y : Float32) : Path
      check_finite x, y
      if @open
        start = @ends.size > 1 ? @ends[-2] &+ 1_u32 : 0_u32
        if @tags.size - start == 1
          @xy.pop(2)
          @tags.pop
          @ends.pop
        end
      end
      @ends << 0_u32
      @open = true
      push x, y, PointTag::On
      self
    end

    # Adds a straight segment to (*x*, *y*) and returns self.
    #
    # Raises `Error` when no contour is open or a coordinate is not finite.
    def line_to(x : Float32, y : Float32) : Path
      check_open
      check_finite x, y
      push x, y, PointTag::On
      self
    end

    # Adds a quadratic Bézier segment through control point (*cx*, *cy*) to
    # (*x*, *y*) and returns self.
    #
    # Raises `Error` when no contour is open or a coordinate is not finite.
    def quad_to(cx : Float32, cy : Float32, x : Float32, y : Float32) : Path
      check_open
      check_finite cx, cy
      check_finite x, y
      push cx, cy, PointTag::Conic
      push x, y, PointTag::On
      self
    end

    # Adds a cubic Bézier segment through control points (*c1x*, *c1y*) and
    # (*c2x*, *c2y*) to (*x*, *y*) and returns self.
    #
    # Raises `Error` when no contour is open or a coordinate is not finite.
    def cubic_to(c1x : Float32, c1y : Float32, c2x : Float32, c2y : Float32, x : Float32, y : Float32) : Path
      check_open
      check_finite c1x, c1y
      check_finite c2x, c2y
      check_finite x, y
      push c1x, c1y, PointTag::Cubic
      push c2x, c2y, PointTag::Cubic
      push x, y, PointTag::On
      self
    end

    # :nodoc: point coordinates, x/y interleaved, `2 * point_count` long; read-only view for `Outline.from_path`
    def xy : Slice(Float32)
      Slice.new(@xy.to_unsafe, @xy.size, read_only: true)
    end

    # :nodoc: tag per point, `point_count` long; read-only view for `Outline.from_path`
    def tags : Slice(PointTag)
      Slice.new(@tags.to_unsafe, @tags.size, read_only: true)
    end

    # :nodoc: last point index per contour, `contour_count` long; read-only view for `Outline.from_path`
    def ends : Slice(UInt32)
      Slice.new(@ends.to_unsafe, @ends.size, read_only: true)
    end

    # :nodoc: total point count
    def point_count : Int32
      @tags.size
    end

    # :nodoc: contour count
    def contour_count : Int32
      @ends.size
    end

    private def push(x : Float32, y : Float32, tag : PointTag) : Nil
      @xy.push x, y
      @tags << tag
      @ends[-1] = (@tags.size - 1).to_u32
    end

    private def check_open : Nil
      raise Error.new(Result::InvalidArgument, "no contour is open; call move_to first") unless @open
    end

    private def check_finite(x : Float32, y : Float32) : Nil
      raise Error.new(Result::InvalidArgument, "coordinates must be finite") unless x.finite? && y.finite?
    end
  end
end
