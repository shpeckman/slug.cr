# src/slug/font.cr
require "atomic"

require "./lib_ft"
require "./types"
require "./error"

module Slug
  # A scalable font face: em-space metrics, CPAL palette selection and
  # variation coordinates.
  #
  # `.open` owns a FreeType library and face; `close` releases them (the
  # garbage collector closes the font eventually, but faces pin large tables,
  # so close explicitly). Every distinct combination of variation coordinates,
  # palette, palette overrides and outline style caches its own glyphs in the
  # atlas, so switching back to an earlier combination is cheap.
  class Font
    # :nodoc:
    #
    # Variation coordinates (16.16 fixed point, every axis) and outline style
    # with their glyph cache key.
    struct VariationState
      getter key : UInt32
      getter coords : Array(LibFT::Fixed)
      getter outline : OutlineStyle

      def initialize(@key : UInt32, @coords : Array(LibFT::Fixed), @outline : OutlineStyle)
      end
    end

    # :nodoc:
    #
    # Variation state index, palette and sorted unique palette overrides with
    # their color glyph cache key. Keys come from one global counter shared
    # with `VariationState`, so they never collide across fonts; states only
    # grow, so keys handed to atlases stay unique for the font's lifetime.
    struct ColorState
      getter key : UInt32
      getter variation : Int32
      getter palette : UInt32
      getter colors : Array(PaletteColor)

      def initialize(@key : UInt32, @variation : Int32, @palette : UInt32, @colors : Array(PaletteColor))
      end
    end

    @@next_key = Atomic(UInt32).new(1_u32)

    @metrics = FontMetrics.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32, 0_u32, ColorFormat::None, 0_u32)
    @axis_count = 0
    @variations = [] of VariationState
    @variation = 0
    @color_states = [] of ColorState
    @color_state = 0
    @closed = false

    # Opens *path* with its own FreeType library and wraps face *face_index*,
    # raising `Error` on failure. The face is owned by the font.
    def self.open(path : String, face_index : Int = 0) : Font
      library = Pointer(LibFT::Library).null
      unless LibFT.Slug_FT_Init_FreeType(pointerof(library)) == 0
        raise Error.new(Result::FreeType, "FT_Init_FreeType failed")
      end
      face = Pointer(LibFT::Face).null
      unless LibFT.Slug_FT_New_Face(library, path, face_index.to_i64, pointerof(face).as(Void*)) == 0
        LibFT.Slug_FT_Done_FreeType(library)
        raise Error.new(Result::FreeType, "cannot open #{path}")
      end
      begin
        new(face, library)
      rescue ex
        LibFT.Slug_FT_Done_Face(face.as(Void*))
        LibFT.Slug_FT_Done_FreeType(library)
        raise ex
      end
    end

    # :nodoc:
    #
    # Wraps the borrowed FreeType *face*, which must outlive the font. The
    # face's variation coordinates at creation are the font's initial
    # instance; change them afterwards with `#variation=`, not on the face, so
    # cached glyphs stay matched to their coordinates.
    def initialize(face : LibFT::Face*)
      @face = face
      @library = Pointer(LibFT::Library).null
      @owns_face = false
      @owns_library = false
      setup
    end

    # :nodoc:
    #
    # Wraps FreeType *face* like `.new` but takes ownership: `#close`
    # releases it, and so does a failure to wrap it.
    def self.adopt(face : LibFT::Face*) : Font
      font = begin
        new(face)
      rescue ex
        LibFT.Slug_FT_Done_Face(face.as(Void*))
        raise ex
      end
      font.own
      font
    end

    protected def own : Nil
      @owns_face = true
    end

    private def initialize(face : LibFT::Face*, library : LibFT::Library*)
      @face = face
      @library = library
      @owns_face = true
      @owns_library = true
      setup
    end

    # Releases the FreeType face and, for `.open`, the library. Idempotent.
    def close : Nil
      return if @closed
      @closed = true
      LibFT.Slug_FT_Done_Face(@face.as(Void*)) if @owns_face
      LibFT.Slug_FT_Done_FreeType(@library) if @owns_library
      nil
    end

    def closed? : Bool
      @closed
    end

    def finalize
      close
    end

    # Returns the font's vertical metrics and color capabilities, re-read by
    # `#variation=`.
    def metrics : FontMetrics
      @metrics
    end

    # Returns the pixel size nearest to *pixels_per_em* at which the cap
    # height spans a whole number of pixels (at least one), so tops and
    # baselines of capitals land on the pixel grid. Account for display scale
    # before calling.
    def snap_size(pixels_per_em : Float32) : Float32
      cap = @metrics.cap_height
      return pixels_per_em unless cap > 0.0_f32 && pixels_per_em > 0.0_f32
      pixels = (pixels_per_em * cap).round(mode: :ties_away)
      pixels = 1.0_f32 if pixels < 1.0_f32
      pixels / cap
    end

    # Returns the selected palette.
    def palette : UInt32
      @color_states[@color_state].palette
    end

    # Selects the CPAL *palette* used for color glyphs emitted afterwards
    # (default 0), keeping the current overrides. Color glyphs are cached per
    # palette, so switching is cheap after first use. Raises `Error` when out
    # of range.
    def palette=(palette : UInt32) : Nil
      ensure_open
      if palette > 0 && palette >= @metrics.palette_count
        raise Error.new(Result::InvalidArgument)
      end
      c = @color_states[@color_state]
      select_color(palette, c.colors)
      nil
    end

    # Returns the properties of *palette*. Raises `Error` when out of range.
    def palette_info(palette : UInt32) : PaletteInfo
      ensure_open
      raise Error.new(Result::InvalidArgument) if palette >= @metrics.palette_count
      data = LibFT::PaletteData.new
      unless LibFT.Slug_FT_Palette_Data_Get(@face, pointerof(data)) == 0
        raise Error.new(Result::FreeType)
      end
      flags = data.palette_flags.null? ? 0_u16 : data.palette_flags[palette]
      name_id = data.palette_name_ids.null? ? 0xFFFF_u16 : data.palette_name_ids[palette]
      PaletteInfo.new(
        (flags & LibFT::PALETTE_FOR_LIGHT_BACKGROUND) != 0,
        (flags & LibFT::PALETTE_FOR_DARK_BACKGROUND) != 0,
        name_id,
        data.num_palette_entries.to_u32)
    end

    # Replaces palette entries for color glyphs emitted afterwards, on top of
    # whichever palette is selected (like CSS `override-colors`). The
    # overrides stay until the next call; an empty array restores the font's
    # colors. A later entry with the same index wins. Each distinct set of
    # overrides caches its own color glyphs, so returning to an earlier set is
    # cheap. Raises `Error` when an index is out of range.
    def palette_colors=(colors : Array(PaletteColor)) : Nil
      ensure_open
      entries = 0_u32
      unless colors.empty?
        data = LibFT::PaletteData.new
        entries = LibFT.Slug_FT_Palette_Data_Get(@face, pointerof(data)) == 0 ? data.num_palette_entries.to_u32 : 0_u32
      end
      colors.each do |c|
        raise Error.new(Result::InvalidArgument) if c.index >= entries
      end

      # Canonical form: sorted by index, the last entry of each index kept, so
      # equal sets share a cache.
      sorted = [] of PaletteColor
      i = colors.size
      while i > 0
        i -= 1
        color = colors[i]
        sorted << color unless sorted.any? { |s| s.index == color.index }
      end
      sorted.sort! { |a, b| a.index <=> b.index }
      select_color(palette, sorted)
      nil
    end

    # Sets how outlines of glyphs emitted afterwards are loaded. Each distinct
    # style caches its own glyphs, so hinted glyphs are stored per size. Draw
    # hinted glyphs at `OutlineStyle#pixels_per_em`, pen on whole pixels, to
    # keep them on the grid. Layers of color glyphs load the same way, so
    # leave hinting off for color fonts. Changes the FreeType face's size.
    # Raises `Error` on invalid values.
    def outline_style=(style : OutlineStyle) : Nil
      ensure_open
      valid = (style.hinting.none? || style.hinting.light? || style.hinting.full?) &&
              style.embolden.finite? && style.embolden >= 0.0_f32
      raise Error.new(Result::InvalidArgument) unless valid

      canonical = style
      if canonical.hinting.none?
        canonical.pixels_per_em = 0.0_f32
        canonical.autohint = false
      else
        unless canonical.pixels_per_em >= 1.0_f32 && canonical.pixels_per_em.finite?
          raise Error.new(Result::InvalidArgument)
        end
        size = (canonical.pixels_per_em * 64.0_f32).round(mode: :ties_away).to_i64
        unless LibFT.Slug_FT_Set_Char_Size(@face.as(Void*), 0_i64, size, 72_u32, 72_u32) == 0
          raise Error.new(Result::FreeType)
        end
      end
      @variation = intern_variation(@variations[@variation].coords, canonical)
      c = @color_states[@color_state]
      select_color(c.palette, c.colors)
      nil
    end

    # Sets the variation design coordinates for glyphs emitted afterwards: one
    # value per axis in the face's axis order and units (e.g. 700 for `wght`),
    # as listed by FreeType's `FT_Get_MM_Var`. Missing trailing axes take
    # their defaults; an empty array selects the default instance. This
    # changes the FreeType face. Metrics are re-read. Raises
    # `Error`(`Result::Unsupported`) for a face without variations (unless
    # *coords* is empty).
    def variation=(coords : Array(Float32)) : Nil
      ensure_open
      n = @axis_count
      raise Error.new(Result::Unsupported) if !coords.empty? && n == 0
      raise Error.new(Result::InvalidArgument) if coords.size > n
      return if n == 0

      outline = @variations[@variation].outline
      fixed = Array(LibFT::Fixed).new(n, 0_i64)
      coords.each_with_index do |c, i|
        unless c.finite? && c.abs < 32768.0_f32
          raise Error.new(Result::InvalidArgument)
        end
        fixed[i] = (c * 65536.0_f32).round(mode: :ties_away).to_i64
      end
      ptr = coords.empty? ? Pointer(LibFT::Fixed).null : fixed.to_unsafe
      error = LibFT.Slug_FT_Set_Var_Design_Coordinates(@face, coords.size.to_u32, ptr)
      raise Error.new(Result::FreeType) if error != 0 && error != -1 # -1: unchanged
      raise Error.new(Result::FreeType) unless read_coords(fixed)
      @variation = intern_variation(fixed, outline)
      read_metrics
      c = @color_states[@color_state]
      select_color(c.palette, c.colors)
      nil
    end

    # :nodoc: underlying FreeType face; valid until `close`, serial access only
    def face : LibFT::Face*
      ensure_open
      @face
    end

    # :nodoc: atlas cache key of the current glyph outlines (variation and outline style)
    def glyph_key : UInt32
      @variations[@variation].key
    end

    # :nodoc: current (variation, palette, overrides) state, the color glyph cache key
    def color_state : ColorState
      @color_states[@color_state]
    end

    # :nodoc: how outlines of the current variation state are loaded
    def outline_style : OutlineStyle
      @variations[@variation].outline
    end

    # :nodoc: variation axis count, 0 for non-variable faces
    def axis_count : Int32
      @axis_count
    end

    private def ensure_open : Nil
      raise Error.new(Result::InvalidArgument, "font is closed") if @closed
    end

    private def setup : Nil
      face = @face.value
      unless (face.face_flags & LibFT::FACE_FLAG_SCALABLE) != 0 && face.units_per_em != 0
        raise Error.new(Result::Unsupported, "face is not scalable")
      end
      read_metrics

      if (face.face_flags & LibFT::FACE_FLAG_MULTIPLE_MASTERS) != 0
        mm = Pointer(LibFT::MMVar).null
        if LibFT.Slug_FT_Get_MM_Var(@face.as(Void*), pointerof(mm).as(Void*)) == 0
          @axis_count = mm.value.num_axis.to_i
          LibFT.Slug_FT_Done_MM_Var(@face.value.glyph.value.library, mm.as(Void*))
        end
      end

      coords = Array(LibFT::Fixed).new(@axis_count, 0_i64)
      raise Error.new(Result::FreeType) unless read_coords(coords)
      @variation = intern_variation(coords, OutlineStyle.new)
      select_color(0_u32, [] of PaletteColor)
    end

    private def read_metrics : Nil
      face = @face.value
      upem = face.units_per_em.to_f32
      palettes = LibFT::PaletteData.new
      palette_count = LibFT.Slug_FT_Palette_Data_Get(@face, pointerof(palettes)) == 0 ? palettes.num_palettes.to_u32 : 0_u32
      @metrics = FontMetrics.new(
        face.ascender.to_f32 / upem,
        face.descender.to_f32 / upem,
        face.height.to_f32 / upem,
        cap_height_units / upem,
        face.units_per_em.to_u32,
        color_format,
        palette_count)
    end

    private def cap_height_units : Float32
      os2 = LibFT.Slug_FT_Get_Sfnt_Table(@face.as(Void*), LibFT::SfntTag::OS2.value).as(LibFT::OS2*)
      if !os2.null? && os2.value.version >= 2 && os2.value.s_cap_height > 0
        return os2.value.s_cap_height.to_f32
      end

      h = LibFT.Slug_FT_Get_Char_Index(@face.as(Void*), 0x48_u64) # 'H'
      if h != 0 &&
         LibFT.Slug_FT_Load_Glyph(@face.as(Void*), h, LibFT::LOAD_NO_SCALE | LibFT::LOAD_NO_HINTING | LibFT::LOAD_NO_BITMAP) == 0 &&
         @face.value.glyph.value.format == LibFT::GLYPH_FORMAT_OUTLINE
        outline = @face.value.glyph.value.outline
        box = LibFT::BBox.new
        LibFT.Slug_FT_Outline_Get_CBox(pointerof(outline), pointerof(box))
        return box.y_max.to_f32
      end
      @face.value.ascender.to_f32
    end

    # COLR version from the table header (big-endian uint16 at offset 0).
    # COLRv1 is out of scope: a v1 table falls back to monochrome.
    private def color_format : ColorFormat
      length = 0_u64
      if LibFT.Slug_FT_Load_Sfnt_Table(@face, LibFT::TAG_COLR, 0_i64, Pointer(LibFT::Byte).null, pointerof(length)) != 0 || length < 2
        return ColorFormat::None
      end
      header = StaticArray(UInt8, 2).new(0_u8)
      read = 2_u64
      unless LibFT.Slug_FT_Load_Sfnt_Table(@face, LibFT::TAG_COLR, 0_i64, header.to_unsafe, pointerof(read)) == 0
        return ColorFormat::None
      end
      header[0] == 0 && header[1] == 0 ? ColorFormat::COLR0 : ColorFormat::None
    end

    private def read_coords(coords : Array(LibFT::Fixed)) : Bool
      return true if @axis_count == 0
      LibFT.Slug_FT_Get_Var_Design_Coordinates(@face.as(Void*), @axis_count.to_u32, coords.to_unsafe) == 0
    end

    private def intern_variation(coords : Array(LibFT::Fixed), outline : OutlineStyle) : Int32
      @variations.each_with_index do |v, i|
        return i if (coords.empty? || v.coords == coords) && same_outline?(v.outline, outline)
      end
      @variations << VariationState.new(next_key, coords.dup, outline)
      @variations.size - 1
    end

    private def intern_color(variation : Int32, palette : UInt32, colors : Array(PaletteColor)) : Int32
      @color_states.each_with_index do |c, i|
        if c.variation == variation && c.palette == palette && same_colors?(c.colors, colors)
          return i
        end
      end
      @color_states << ColorState.new(next_key, variation, palette, colors.dup)
      @color_states.size - 1
    end

    # Switches to the color state of the current variation with this palette and these overrides.
    private def select_color(palette : UInt32, colors : Array(PaletteColor)) : Nil
      @color_state = intern_color(@variation, palette, colors)
    end

    private def same_outline?(a : OutlineStyle, b : OutlineStyle) : Bool
      a.hinting == b.hinting && a.pixels_per_em == b.pixels_per_em &&
        a.autohint? == b.autohint? && a.embolden == b.embolden
    end

    # Bitwise comparison, matching the C memcmp of the canonical override sets.
    private def same_colors?(a : Array(PaletteColor), b : Array(PaletteColor)) : Bool
      return false unless a.size == b.size
      a.each_with_index do |x, i|
        y = b[i]
        return false unless x.index == y.index
        4.times { |k| return false unless x.color[k].unsafe_as(UInt32) == y.color[k].unsafe_as(UInt32) }
      end
      true
    end

    private def next_key : UInt32
      @@next_key.add(1_u32)
    end
  end
end
