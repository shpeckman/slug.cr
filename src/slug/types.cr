# src/slug/types.cr
module Slug
  # Width in texels of every atlas texture.
  TEXTURE_WIDTH = 4096_u32

  # :nodoc: 16-bit texel y coordinates
  MAX_ROWS = 65536_u32

  # :nodoc: 8-bit band max per axis
  MAX_BANDS = 256_u32

  # :nodoc:
  BAND_EPSILON = 1.0_f32 / 1024.0_f32

  # :nodoc: flag bits in the packed band info (`Instance#origin[3]`); the shader sees them shifted down by 16
  FLAG_EVEN_ODD = 1_u32 << 28

  # :nodoc: set per style, OR-ed into the band info at emission
  FLAG_WEIGHT = 1_u32 << 29

  # :nodoc: outer contours counter-clockwise (y up); selects the dilation shift sign
  FLAG_REVERSED = 1_u32 << 31

  # Color glyph table found in a font.
  enum ColorFormat
    # Monochrome outlines only.
    None
    # COLR version 0: stacked solid layers.
    COLR0
  end

  # How glyph outlines are fitted to the pixel grid.
  enum Hinting
    # Design outlines, independent of the size.
    None
    # Fitted vertically (FreeType's light target).
    Light
    # Fitted on both axes (FreeType's normal target).
    Full
  end

  # Fill rule of a path.
  enum FillRule
    Nonzero
    EvenOdd
  end

  # Vertical font metrics in em units, plus color capabilities.
  struct FontMetrics
    # Distance from baseline to ascender line (positive).
    getter ascender : Float32
    # Distance from baseline to descender line (negative).
    getter descender : Float32
    # Baseline-to-baseline distance.
    getter line_height : Float32
    # OS/2 sCapHeight, or the height of 'H' when absent.
    getter cap_height : Float32
    # Font units per em.
    getter units_per_em : UInt32
    # Highest COLR version present.
    getter color_format : ColorFormat
    # CPAL palettes (0 without CPAL).
    getter palette_count : UInt32

    # :nodoc:
    def initialize(@ascender : Float32, @descender : Float32, @line_height : Float32, @cap_height : Float32,
                   @units_per_em : UInt32, @color_format : ColorFormat, @palette_count : UInt32)
    end
  end

  # CPAL palette properties.
  struct PaletteInfo
    # Marked as usable with light backgrounds.
    getter? light_background : Bool
    # Marked as usable with dark backgrounds.
    getter? dark_background : Bool
    # `name` table ID of the palette's name; 0xFFFF without one.
    getter name_id : UInt16
    # Colors per palette (the same for every palette).
    getter entry_count : UInt32

    # :nodoc:
    def initialize(@light_background : Bool, @dark_background : Bool, @name_id : UInt16, @entry_count : UInt32)
    end
  end

  # Replacement for one palette entry (see `Font#palette_colors=`).
  struct PaletteColor
    # Palette entry, below `PaletteInfo#entry_count`.
    property index : UInt32
    # Straight-alpha sRGB RGBA.
    property color : StaticArray(Float32, 4)

    def initialize(@index : UInt32, @color : StaticArray(Float32, 4))
    end
  end

  # How a font's outlines are loaded (see `Font#outline_style=`).
  struct OutlineStyle
    # Grid fitting. Default none.
    property hinting : Hinting
    # Size the outlines are fitted for; required unless hinting is none.
    property pixels_per_em : Float32
    # Uses FreeType's autohinter instead of the font's instructions.
    property? autohint : Bool
    # Outline growth in em, stored in the atlas: faster than `Style#dilation`.
    property embolden : Float32

    def initialize(@hinting : Hinting = :none, @pixels_per_em : Float32 = 0.0_f32,
                   @autohint : Bool = false, @embolden : Float32 = 0.0_f32)
    end
  end

  # Atlas creation parameters. Every field takes the documented default.
  struct AtlasDesc
    # Rows reserved per texture. Default 64.
    property initial_rows : UInt32
    # Upper bound of bands per axis, 1..256. Default 16.
    property max_bands : UInt32
    # Max em-space error when splitting cubics. Default 1/2048.
    property cubic_tolerance : Float32
    # Band count choice per glyph: the count with the fewest curves per band
    # (the per-pixel loop length) is taken, or the smallest count within this
    # fraction above it. 0 (default) is fastest to render; e.g. 0.1 saves
    # ~7% band memory for ~5% more curves per pixel.
    property band_slack : Float32

    def initialize(@initial_rows : UInt32 = 64_u32, @max_bands : UInt32 = 16_u32,
                   @cubic_tolerance : Float32 = 1.0_f32 / 2048.0_f32, @band_slack : Float32 = 0.0_f32)
    end
  end

  # Read-only view of one atlas texture. Texels are stored row-major with
  # `TEXTURE_WIDTH` texels per row.
  struct Plane
    # Texel bytes, `rows * width * texel_size` long. Do not modify.
    getter data : Bytes
    # Texels per row, always `TEXTURE_WIDTH`.
    getter width : UInt32
    # Allocated rows; the GPU texture height.
    getter rows : UInt32
    # Bytes per texel.
    getter texel_size : UInt32
    # Texels written, counted linearly (row * width + x). Only grows.
    getter used : UInt64

    # :nodoc:
    def initialize(@data : Bytes, @rows : UInt32, @texel_size : UInt32, @used : UInt64)
      @width = TEXTURE_WIDTH
    end
  end

  # Placement data of one outline inside the atlas.
  struct Glyph
    # Horizontal advance in em.
    property advance : Float32
    # Em-space bounding box: x min, y min, x max, y max.
    property bounds : StaticArray(Float32, 4)
    # Band index scale for x and y.
    property band_scale : StaticArray(Float32, 2)
    # Band index offset for x and y.
    property band_offset : StaticArray(Float32, 2)
    # Band texture location: x | y << 16.
    property location : UInt32
    # Band max x | band max y << 16 | even-odd flag << 28 | reversed
    # orientation << 31 (the weight flag, bit 29, is set per style).
    property band_info : UInt32
    # True when the glyph has no outline (e.g. space).
    property? empty : Bool

    # :nodoc:
    def initialize(@advance : Float32 = 0.0_f32,
                   @bounds : StaticArray(Float32, 4) = StaticArray(Float32, 4).new(0.0_f32),
                   @band_scale : StaticArray(Float32, 2) = StaticArray(Float32, 2).new(0.0_f32),
                   @band_offset : StaticArray(Float32, 2) = StaticArray(Float32, 2).new(0.0_f32),
                   @location : UInt32 = 0_u32, @band_info : UInt32 = 0_u32, @empty : Bool = false)
    end
  end

  # A path stored in the atlas, ready for `Slug.emit_shape`.
  struct Shape
    # Outline normalized to the unit square.
    property glyph : Glyph
    # Path coordinates of the normalized origin (path bounds minimum).
    property origin : StaticArray(Float32, 2)
    # Path units per normalized unit (largest path extent).
    property scale : Float32

    # :nodoc:
    def initialize(@glyph : Glyph = Glyph.new,
                   @origin : StaticArray(Float32, 2) = StaticArray(Float32, 2).new(0.0_f32),
                   @scale : Float32 = 0.0_f32)
    end
  end

  # One drawn outline, rendered as an instance of a 4-vertex triangle strip
  # whose corners the vertex shader derives (with dilation normals and inverse
  # Jacobian) from these fields. A monochrome glyph is one instance; a color
  # glyph is one instance per layer. 84 bytes.
  struct Instance
    # Outline em bounds: x min, y min, x max, y max.
    property rect : StaticArray(Float32, 4)
    # Em-to-object linear part a, b, c, d (see `Style#transform`).
    property xform : StaticArray(Float32, 4)
    # Object translation xy (pen position folded in), packed glyph location z,
    # packed band info w.
    property origin : StaticArray(Float32, 4)
    # Band scale xy, band offset zw.
    property bnd : StaticArray(Float32, 4)
    # Premultiplied color.
    property col : StaticArray(Float32, 4)
    # Outline dilation in pixels.
    property dilation : Float32

    # :nodoc:
    def initialize(@rect : StaticArray(Float32, 4) = StaticArray(Float32, 4).new(0.0_f32),
                   @xform : StaticArray(Float32, 4) = StaticArray(Float32, 4).new(0.0_f32),
                   @origin : StaticArray(Float32, 4) = StaticArray(Float32, 4).new(0.0_f32),
                   @bnd : StaticArray(Float32, 4) = StaticArray(Float32, 4).new(0.0_f32),
                   @col : StaticArray(Float32, 4) = StaticArray(Float32, 4).new(0.0_f32),
                   @dilation : Float32 = 0.0_f32)
    end
  end

  # Transform, color and effects applied to emitted glyphs and shapes.
  struct Style
    # Affine em-to-object transform {a, b, c, d, e, f}:
    # x' = a*x + c*y + e, y' = b*x + d*y + f.
    # Text at size s with origin (x, y): {s, 0, 0, s, x, y}.
    property transform : StaticArray(Float32, 6)
    # Straight-alpha RGBA; premultiplied on emission. The foreground color of
    # color glyphs.
    property color : StaticArray(Float32, 4)
    # Square-root coverage boost, thickening light or small text optically
    # (the reference shader's SLUG_WEIGHT, selectable per style).
    property? optical_weight : Bool
    # Outline offset in pixels, the same distance in every direction: positive
    # values embolden (faux bold, or an outline when drawn under the regular
    # text) with round corners, negative values thin. Growth below 1 px moves
    # edges along the sampling rays (corners within a third of a pixel). Draws
    # containing dilated instances use the effects shader variant.
    property dilation : Float32
    # Draws color glyphs as their monochrome fallback outline in the style color.
    property? monochrome : Bool

    def initialize(transform : StaticArray(Float32, 6)? = nil, color : StaticArray(Float32, 4)? = nil,
                   @optical_weight : Bool = false, @dilation : Float32 = 0.0_f32, @monochrome : Bool = false)
      @transform = transform || StaticArray[1.0_f32, 0.0_f32, 0.0_f32, 1.0_f32, 0.0_f32, 0.0_f32]
      @color = color || StaticArray[1.0_f32, 1.0_f32, 1.0_f32, 1.0_f32]
    end
  end

  # A glyph placed at an em-space pen position, e.g. from a shaper.
  struct Placement
    # Glyph index in the font (not a code point).
    property glyph_id : UInt32
    # Pen x in em units.
    property x : Float32
    # Pen y in em units (y up).
    property y : Float32

    def initialize(@glyph_id : UInt32, @x : Float32 = 0.0_f32, @y : Float32 = 0.0_f32)
    end
  end

  # Layout extent of a text, in em units (multiply by the size for object units).
  struct TextMetrics
    # Pen advance of the widest line, kerning included.
    getter advance : Float32
    # Ink box of all glyphs (color layers included): x min, y min, x max,
    # y max; zero without ink.
    getter bounds : StaticArray(Float32, 4)
    # Line count: newlines + 1, or 0 for empty text.
    getter lines : UInt32
    # Baseline-to-baseline distance used for line breaks.
    getter line_height : Float32

    # :nodoc:
    def initialize(@advance : Float32, @bounds : StaticArray(Float32, 4), @lines : UInt32,
                   @line_height : Float32)
    end
  end
end
