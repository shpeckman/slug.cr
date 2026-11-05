# src/slug/half.cr
module Slug
  # :nodoc:
  #
  # IEEE 754 half-precision conversion, ported from util.c: round to nearest
  # even, overflow to infinity, subnormals on both sides.
  module Half
    extend self

    def from_float(value : Float32) : UInt16
      x = value.unsafe_as(UInt32)
      sign = (x >> 16) & 0x8000_u32
      exponent = (x >> 23) & 0xFF_u32
      mantissa = x & 0x007F_FFFF_u32

      return (sign | 0x7C00_u32 | (mantissa == 0 ? 0_u32 : 0x200_u32)).to_u16 if exponent == 0xFF_u32

      e = exponent.to_i32 - 127 + 15
      return (sign | 0x7C00_u32).to_u16 if e >= 31

      if e <= 0
        return sign.to_u16 if e < -10
        mantissa |= 0x0080_0000_u32
        shift = 14 - e
        h = mantissa >> shift
        rest = mantissa & ((1_u32 << shift) &- 1_u32)
        halfway = 1_u32 << (shift - 1)
        h &+= 1_u32 if rest > halfway || (rest == halfway && (h & 1_u32) != 0_u32)
        return (sign | h).to_u16
      end

      h = (e.to_u32 << 10) | (mantissa >> 13)
      rest = mantissa & 0x1FFF_u32
      h &+= 1_u32 if rest > 0x1000_u32 || (rest == 0x1000_u32 && (h & 1_u32) != 0_u32)
      (sign | h).to_u16
    end

    def to_float(half : UInt16) : Float32
      sign = (half.to_u32 & 0x8000_u32) << 16
      exponent = (half.to_i32 >> 10) & 0x1F
      mantissa = half.to_u32 & 0x3FF_u32

      if exponent == 0
        return sign.unsafe_as(Float32) if mantissa == 0
        exponent = 1
        while (mantissa & 0x400_u32) == 0
          mantissa <<= 1
          exponent -= 1
        end
        mantissa &= 0x3FF_u32
      end

      x = sign | ((exponent + 112).to_u32 << 23) | (mantissa << 13)
      x.unsafe_as(Float32)
    end
  end
end
