# src/slug/utf8.cr
module Slug
  # :nodoc:
  #
  # Strict byte-level UTF-8 decoding, ported from util.c. Every malformed
  # sequence yields U+FFFD; the returned next index skips the lead byte when
  # the lead is invalid, stops at a missing or bad continuation, and skips the
  # whole sequence when it decodes to an overlong form, a surrogate or a value
  # past U+10FFFF.
  module UTF8
    extend self

    REPLACEMENT = 0xFFFD_u32

    # *index* must be within *bytes*.
    def next(bytes : Bytes, index : Int32) : {UInt32, Int32}
      p = index
      c = bytes[p].to_u32

      return {c, p + 1} if c < 0x80_u32

      extra : Int32
      minimum : UInt32
      if (c & 0xE0_u32) == 0xC0_u32
        extra = 1
        c &= 0x1F_u32
        minimum = 0x80_u32
      elsif (c & 0xF0_u32) == 0xE0_u32
        extra = 2
        c &= 0x0F_u32
        minimum = 0x800_u32
      elsif (c & 0xF8_u32) == 0xF0_u32
        extra = 3
        c &= 0x07_u32
        minimum = 0x1_0000_u32
      else
        return {REPLACEMENT, p + 1}
      end

      k = 1
      while k <= extra
        return {REPLACEMENT, p + k} if p + k >= bytes.size || (bytes[p + k] & 0xC0_u8) != 0x80_u8
        c = (c << 6) | (bytes[p + k] & 0x3F_u8).to_u32
        k += 1
      end

      index = p + extra + 1
      return {REPLACEMENT, index} if c < minimum || c > 0x10_FFFF_u32 || (0xD800_u32 <= c <= 0xDFFF_u32)
      {c, index}
    end
  end
end
