# src/slug/lib_ft.cr

module Slug
  # :nodoc:
  #
  # FreeType C bindings, LP64 ABI (FreeType >= 2.12 headers; `FT_Outline`
  # point/contour counts are `unsigned short` there). Scope: face lifecycle
  # (file and memory), sizes (char, pixel, fixed strikes, extra size
  # objects), transforms, metrics, cmap/kerning, glyph load/render/embolden,
  # outline decompose/embolden/CBox/rasterize, SFNT OS/2, MM variations,
  # CPAL palettes and COLRv0 layers. COLRv1 (FT_Get_Color_Glyph_Paint and
  # friends) is deliberately absent. Shards that load faces themselves
  # (asekii-app) use these bindings instead of their own.
  @[Link("freetype")]
  lib LibFT
    alias Bool = UInt8
    alias Byte = UInt8
    alias Error = Int32
    alias Int = Int32
    alias UInt = UInt32
    alias Short = Int16
    alias UShort = UInt16
    alias Long = LibC::Long
    alias ULong = LibC::ULong
    alias Pos = LibC::Long
    alias Fixed = LibC::Long
    alias F26Dot6 = LibC::Long

    alias Library = Void
    alias CharMap = Void

    # Face flags, bit mask on `FaceRec#face_flags`.
    FACE_FLAG_SCALABLE         = Long.new(1 << 0)
    FACE_FLAG_KERNING          = Long.new(1 << 6)
    FACE_FLAG_MULTIPLE_MASTERS = Long.new(1 << 8)
    FACE_FLAG_COLOR            = Long.new(1 << 14)

    # Style flags, bit mask on `FaceRec#style_flags`.
    STYLE_FLAG_ITALIC = Long.new(1 << 0)
    STYLE_FLAG_BOLD   = Long.new(1 << 1)

    # `FT_Load_Glyph` flags (FT_Int32).
    LOAD_DEFAULT        = 0
    LOAD_NO_SCALE       = 1 << 0
    LOAD_NO_HINTING     = 1 << 1
    LOAD_RENDER         = 1 << 2
    LOAD_NO_BITMAP      = 1 << 3
    LOAD_FORCE_AUTOHINT = 1 << 5
    LOAD_TARGET_NORMAL  = 0 << 16
    LOAD_TARGET_LIGHT   = 1 << 16
    LOAD_TARGET_MONO    = 2 << 16
    LOAD_COLOR          = 1 << 20
    LOAD_NO_SVG         = 1 << 24

    # `FT_Get_Kerning` modes.
    KERNING_DEFAULT  = 0
    KERNING_UNFITTED = 1
    KERNING_UNSCALED = 2

    # `Outline#flags` bits.
    OUTLINE_NONE          =   0
    OUTLINE_EVEN_ODD_FILL = 0x2

    # `Bitmap#pixel_mode` values.
    PIXEL_MODE_MONO = 1_u8
    PIXEL_MODE_GRAY = 2_u8
    PIXEL_MODE_BGRA = 7_u8

    # Fourcc glyph formats; `GlyphSlotRec#format` is an `unsigned long` enum.
    GLYPH_FORMAT_OUTLINE = ULong.new(0x6F75746C) # 'outl'
    GLYPH_FORMAT_BITMAP  = ULong.new(0x62697473) # 'bits'

    # SFNT table tag (FT_ULong), for `FT_Load_Sfnt_Table`.
    TAG_COLR = ULong.new(0x434F4C52) # 'COLR'

    # CPAL palette flags (FT_UShort).
    PALETTE_FOR_LIGHT_BACKGROUND = UShort.new(0x01)
    PALETTE_FOR_DARK_BACKGROUND  = UShort.new(0x02)

    enum RenderMode
      Normal = 0
      Light  = 1
      Mono   = 2
      Lcd    = 3
      LcdV   = 4
      Sdf    = 5
    end

    enum SfntTag
      Head = 0
      MaxP = 1
      OS2  = 2
    end

    struct Generic
      data : Void*
      finalizer : Void* -> Void
    end

    struct ListRec
      head : Void*
      tail : Void*
    end

    struct Vector
      x : Pos
      y : Pos
    end

    struct Matrix
      xx : Fixed
      xy : Fixed
      yx : Fixed
      yy : Fixed
    end

    struct BBox
      x_min : Pos
      y_min : Pos
      x_max : Pos
      y_max : Pos
    end

    struct BitmapSize
      height : Short
      width : Short
      size : Pos
      x_ppem : Pos
      y_ppem : Pos
    end

    struct SizeMetrics
      x_ppem : UShort
      y_ppem : UShort
      x_scale : Fixed
      y_scale : Fixed
      ascender : Pos
      descender : Pos
      height : Pos
      max_advance : Pos
    end

    struct SizeRec
      face : Void*
      generic : Generic
      metrics : SizeMetrics
      internal : Void*
    end

    struct GlyphMetrics
      width : Pos
      height : Pos
      hori_bearing_x : Pos
      hori_bearing_y : Pos
      hori_advance : Pos
      vert_bearing_x : Pos
      vert_bearing_y : Pos
      vert_advance : Pos
    end

    struct Bitmap
      rows : UInt
      width : UInt
      pitch : Int
      buffer : Byte*
      num_grays : UShort
      pixel_mode : Byte
      palette_mode : Byte
      palette : Void*
    end

    struct Outline
      n_contours : UShort
      n_points : UShort
      points : Vector*
      tags : Byte*
      contours : UShort*
      flags : Int
    end

    struct OutlineFuncs
      move_to : Vector*, Void* -> Int
      line_to : Vector*, Void* -> Int
      conic_to : Vector*, Vector*, Void* -> Int
      cubic_to : Vector*, Vector*, Vector*, Void* -> Int
      shift : Int
      delta : Pos
    end

    struct GlyphSlotRec
      library : Library*
      face : FaceRec*
      next : GlyphSlotRec*
      glyph_index : UInt
      generic : Generic
      metrics : GlyphMetrics
      linear_hori_advance : Fixed
      linear_vert_advance : Fixed
      advance : Vector
      format : ULong
      bitmap : Bitmap
      bitmap_left : Int
      bitmap_top : Int
      outline : Outline
      num_subglyphs : UInt
      subglyphs : Void*
      control_data : Void*
      control_len : LibC::Long
      lsb_delta : Pos
      rsb_delta : Pos
      other : Void*
      internal : Void*
    end

    alias GlyphSlot = GlyphSlotRec

    struct FaceRec
      num_faces : Long
      face_index : Long
      face_flags : Long
      style_flags : Long
      num_glyphs : Long
      family_name : UInt8*
      style_name : UInt8*
      num_fixed_sizes : Int
      available_sizes : BitmapSize*
      num_charmaps : Int
      charmaps : Void*
      generic : Generic
      bbox : BBox
      units_per_em : UShort
      ascender : Short
      descender : Short
      height : Short
      max_advance_width : Short
      max_advance_height : Short
      underline_position : Short
      underline_thickness : Short
      glyph : GlyphSlotRec*
      size : SizeRec*
      charmap : CharMap*
      driver : Void*
      memory : Void*
      stream : Void*
      sizes_list : ListRec
      autohint : Generic
      extensions : Void*
      internal : Void*
    end

    alias Face = FaceRec

    # CPAL color, BGRA byte order.
    struct Color
      blue : Byte
      green : Byte
      red : Byte
      alpha : Byte
    end

    struct PaletteData
      num_palettes : UShort
      palette_name_ids : UShort*
      palette_flags : UShort*
      num_palette_entries : UShort
      palette_entry_name_ids : UShort*
    end

    # COLRv0 layer iterator; zero-initialize before the first call.
    struct LayerIterator
      num_layers : UInt
      layer : UInt
      p : Byte*
    end

    # OS/2 table (TrueType), big struct returned by `FT_Get_Sfnt_Table`.
    struct OS2
      version : UShort
      x_avg_char_width : Short
      us_weight_class : UShort
      us_width_class : UShort
      fs_type : UShort
      y_subscript_x_size : Short
      y_subscript_y_size : Short
      y_subscript_x_offset : Short
      y_subscript_y_offset : Short
      y_superscript_x_size : Short
      y_superscript_y_size : Short
      y_superscript_x_offset : Short
      y_superscript_y_offset : Short
      y_strikeout_size : Short
      y_strikeout_position : Short
      s_family_class : Short
      panose : Byte[10]
      ul_unicode_range1 : ULong
      ul_unicode_range2 : ULong
      ul_unicode_range3 : ULong
      ul_unicode_range4 : ULong
      ach_vend_id : Int8[4]
      fs_selection : UShort
      us_first_char_index : UShort
      us_last_char_index : UShort
      s_typo_ascender : Short
      s_typo_descender : Short
      s_typo_line_gap : Short
      us_win_ascent : UShort
      us_win_descent : UShort
      ul_code_page_range1 : ULong
      ul_code_page_range2 : ULong
      sx_height : Short
      s_cap_height : Short
      us_default_char : UShort
      us_break_char : UShort
      us_max_context : UShort
      us_lower_optical_point_size : UShort
      us_upper_optical_point_size : UShort
    end

    struct VarAxis
      name : UInt8*
      minimum : Fixed
      def_value : Fixed
      maximum : Fixed
      tag : ULong
      strid : UInt
    end

    struct VarNamedStyle
      coords : Fixed*
      strid : UInt
      psid : UInt
    end

    struct MMVar
      num_axis : UInt
      num_designs : UInt
      num_namedstyles : UInt
      axis : VarAxis*
      namedstyle : VarNamedStyle*
    end

    fun Slug_FT_Init_FreeType = FT_Init_FreeType(alibrary : Library**) : Error
    fun Slug_FT_Done_FreeType = FT_Done_FreeType(library : Library*) : Error
    fun Slug_FT_New_Face = FT_New_Face(library : Library*, filepathname : UInt8*, face_index : Long, aface : Void*) : Error
    fun Slug_FT_Done_Face = FT_Done_Face(face : Void*) : Error

    fun Slug_FT_Set_Char_Size = FT_Set_Char_Size(face : Void*, char_width : F26Dot6, char_height : F26Dot6, horz_resolution : UInt, vert_resolution : UInt) : Error
    fun Slug_FT_Set_Pixel_Sizes = FT_Set_Pixel_Sizes(face : Face*, pixel_width : UInt, pixel_height : UInt) : Error
    fun Slug_FT_Select_Size = FT_Select_Size(face : Void*, strike_index : Int) : Error
    fun Slug_FT_New_Size = FT_New_Size(face : Void*, size : SizeRec**) : Error
    fun Slug_FT_Activate_Size = FT_Activate_Size(size : SizeRec*) : Error
    fun Slug_FT_Done_Size = FT_Done_Size(size : SizeRec*) : Error
    fun Slug_FT_Set_Transform = FT_Set_Transform(face : Void*, matrix : Matrix*, delta : Vector*) : Void

    fun Slug_FT_Load_Glyph = FT_Load_Glyph(face : Void*, glyph_index : UInt, load_flags : Int32) : Error
    fun Slug_FT_Render_Glyph = FT_Render_Glyph(slot : Void*, render_mode : Int32) : Error
    fun Slug_FT_GlyphSlot_Embolden = FT_GlyphSlot_Embolden(slot : Void*) : Void

    fun Slug_FT_Get_Char_Index = FT_Get_Char_Index(face : Void*, charcode : ULong) : UInt
    fun Slug_FT_Get_First_Char = FT_Get_First_Char(face : Face*, agindex : UInt*) : ULong
    fun Slug_FT_Get_Next_Char = FT_Get_Next_Char(face : Face*, char_code : ULong, agindex : UInt*) : ULong
    fun Slug_FT_Get_Kerning = FT_Get_Kerning(face : Face*, left_glyph : UInt, right_glyph : UInt, kern_mode : UInt, akerning : Vector*) : Error

    fun Slug_FT_Get_Sfnt_Table = FT_Get_Sfnt_Table(face : Void*, tag : Int32) : Void*
    fun Slug_FT_Load_Sfnt_Table = FT_Load_Sfnt_Table(face : Face*, tag : ULong, offset : Long, buffer : Byte*, length : ULong*) : Error

    fun Slug_FT_Outline_Decompose = FT_Outline_Decompose(outline : Outline*, func_interface : OutlineFuncs*, user : Void*) : Error
    fun Slug_FT_Outline_Get_CBox = FT_Outline_Get_CBox(outline : Outline*, acbox : BBox*) : Void
    fun Slug_FT_Outline_EmboldenXY = FT_Outline_EmboldenXY(outline : Void*, xstrength : Pos, ystrength : Pos) : Error
    fun Slug_FT_Outline_Get_Bitmap = FT_Outline_Get_Bitmap(library : Library*, outline : Outline*, abitmap : Bitmap*) : Error

    fun Slug_FT_Get_MM_Var = FT_Get_MM_Var(face : Void*, amaster : Void*) : Error
    fun Slug_FT_Done_MM_Var = FT_Done_MM_Var(library : Library*, amaster : Void*) : Error
    fun Slug_FT_Set_Var_Design_Coordinates = FT_Set_Var_Design_Coordinates(face : Face*, num_coords : UInt, coords : Fixed*) : Error
    fun Slug_FT_Get_Var_Design_Coordinates = FT_Get_Var_Design_Coordinates(face : Void*, num_coords : UInt, coords : Fixed*) : Error

    fun Slug_FT_Palette_Data_Get = FT_Palette_Data_Get(face : Face*, apalette_data : PaletteData*) : Error
    fun Slug_FT_Palette_Select = FT_Palette_Select(face : Face*, palette_index : UShort, apalette : Color**) : Error
    fun Slug_FT_Get_Color_Glyph_Layer = FT_Get_Color_Glyph_Layer(face : Face*, glyph_index : UInt, aglyph_index : UInt*, acolor_index : UInt*, iterator : LayerIterator*) : Bool
  end
end
