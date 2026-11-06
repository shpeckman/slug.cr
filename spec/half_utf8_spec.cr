# spec/half_utf8_spec.cr
require "./spec_helper"

# Ports test_half and test_utf8 from tests/test_slug.c of the C library.
describe Slug::Half do
  it "round trips every non-NaN half value" do
    mismatches = 0
    0x10000.times do |h|
      next if (h & 0x7C00) == 0x7C00 && (h & 0x3FF) != 0 # NaN
      mismatches += 1 if Slug::Half.from_float(Slug::Half.to_float(h.to_u16)) != h
    end
    mismatches.should eq 0
  end

  it "converts known values" do
    Slug::Half.from_float(1.0_f32).should eq 0x3C00_u16
    Slug::Half.from_float(65520.0_f32).should eq 0x7C00_u16                        # overflow rounds to inf
    Slug::Half.from_float(1.0_f32 + 1.0_f32 / 2048.0_f32).should eq 0x3C00_u16     # ties to even (down)
    Slug::Half.from_float(1.0_f32 + 3.0_f32 / 2048.0_f32).should eq 0x3C02_u16     # ties to even (up)
    Slug::Half.from_float(5.96046448e-8_f32).should eq 0x0001_u16                  # smallest subnormal
  end
end

describe Slug::UTF8 do
  cases = [
    {"A", [0x41_u32]},
    {"\xC3\xA4", [0xE4_u32]},
    {"\xE2\x82\xAC", [0x20AC_u32]},
    {"\xF0\x9F\x98\x80", [0x1F600_u32]},
    {"\xC0\xAF", [0xFFFD_u32]},          # overlong
    {"\xED\xA0\x80", [0xFFFD_u32]},      # surrogate
    {"\xE2\x82", [0xFFFD_u32]},          # truncated
    {"\xFF" + "A", [0xFFFD_u32, 0x41_u32]},
    {"\xC3" + "A", [0xFFFD_u32, 0x41_u32]},
  ]

  it "decodes valid and invalid sequences" do
    cases.each_with_index do |(string, expected), c|
      bytes = string.to_slice
      decoded = [] of UInt32
      i = 0
      while i < bytes.size
        cp, i = Slug::UTF8.next(bytes, i)
        decoded << cp
      end
      decoded.should eq(expected), "case #{c}: #{decoded.map { |cp| "U+%04X" % cp }}"
      Slug::UTF8.count(bytes).should eq(expected.size)
    end
  end
end
