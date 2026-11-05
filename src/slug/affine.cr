# src/slug/affine.cr
module Slug
  # :nodoc:
  #
  # Affine map x' = a*x + c*y + e, y' = b*x + d*y + f (the `Style#transform` layout).
  struct Affine
    property a : Float32
    property b : Float32
    property c : Float32
    property d : Float32
    property e : Float32
    property f : Float32

    def initialize(@a : Float32, @b : Float32, @c : Float32, @d : Float32, @e : Float32, @f : Float32)
    end

    def self.identity : Affine
      new 1.0_f32, 0.0_f32, 0.0_f32, 1.0_f32, 0.0_f32, 0.0_f32
    end

    # Returns self applied after *other*.
    def *(other : Affine) : Affine
      Affine.new(
        a * other.a + c * other.b, b * other.a + d * other.b,
        a * other.c + c * other.d, b * other.c + d * other.d,
        a * other.e + c * other.f + e, b * other.e + d * other.f + f)
    end

    # Returns the inverse, or nil when the map is singular.
    def invert : Affine?
      det = a * d - b * c
      return nil if det == 0.0_f32 || det.nan?
      ia = d / det
      ib = -b / det
      ic = -c / det
      id = a / det
      Affine.new(ia, ib, ic, id, -(ia * e + ic * f), -(ib * e + id * f))
    end
  end
end
