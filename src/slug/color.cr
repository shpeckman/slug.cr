# src/slug/color.cr

require "./result"
require "./error"
require "./types"
require "./lib_ft"
require "./affine"

module Slug
  # :nodoc:
  #
  # One drawn layer of a COLRv0 color glyph, in the base glyph's em space: the
  # layer `outline` filled with the solid straight-sRGB `color`. `transform`
  # is the identity for v0 (layer outlines already live in base em); it keeps
  # emission uniform. A `foreground` layer takes the style color instead, its
  # alpha multiplied by `color[3]`.
  struct ColorLayer
    property outline : Glyph
    property transform : Affine
    property color : StaticArray(Float32, 4)
    property? foreground : Bool

    def initialize(@outline : Glyph = Glyph.new, @transform : Affine = Affine.identity,
                   @color : StaticArray(Float32, 4) = StaticArray(Float32, 4).new(0.0_f32),
                   @foreground : Bool = false)
    end
  end

  # :nodoc:
  #
  # Cached COLR expansion of one glyph for one palette state. `color` is set
  # when the glyph has COLR data; with `count` 0 it draws nothing. With
  # `color` false the glyph is monochrome and `bounds` are zero.
  struct ColorGlyph
    property first : UInt32
    property count : UInt32
    property bounds : StaticArray(Float32, 4)
    property? color : Bool

    def initialize(@first : UInt32 = 0_u32, @count : UInt32 = 0_u32,
                   @bounds : StaticArray(Float32, 4) = StaticArray(Float32, 4).new(0.0_f32),
                   @color : Bool = false)
    end
  end

  # :nodoc:
  #
  # Growable list of layers produced by `Color.build`; `color` is set when the
  # glyph has COLR data.
  class LayerList
    property items = [] of ColorLayer
    property? color = false

    def clear : Nil
      @items.clear
      @color = false
    end
  end

  # :nodoc:
  #
  # COLRv0/CPAL color glyph expansion (the v0 portions of color.c). Each color
  # glyph is a stack of solid layers, bottom first; every layer references a
  # layer outline glyph that must also live in the atlas. COLRv1 paint graphs
  # are out of scope: a glyph without v0 layers is monochrome.
  module Color
    extend self

    # Expands *glyph_id* for the font's current palette. With *layers*, the
    # solid layers are appended to it (adding layer outlines to *atlas*) and
    # its `color` flag records whether the glyph has COLR data. With
    # *collect*, only the layer outline glyph ids are gathered and no atlas
    # state is touched.
    def build(atlas : Atlas, font : Font, glyph_id : UInt32, layers : LayerList?, collect : Array(UInt32)?) : Result
      return Result::Ok if font.metrics.color_format.none?

      face = font.face
      palette : Array(StaticArray(Float32, 4))? = nil
      palette_loaded = false
      iterator = LibFT::LayerIterator.new
      layer_glyph = uninitialized LibFT::UInt
      color_index = uninitialized LibFT::UInt

      # COLR v0: solid layers, bottom first.
      result = Result::Ok
      while result.ok? && LibFT.Slug_FT_Get_Color_Glyph_Layer(face, glyph_id, pointerof(layer_glyph), pointerof(color_index), pointerof(iterator)) != 0
        unless palette_loaded
          palette = load_palette(font, face)
          palette_loaded = true
        end
        if list = layers
          list.color = true
          result = fill(atlas, font, layer_glyph, color_index.to_u16, palette, list)
        elsif ids = collect
          ids << layer_glyph
        end
      end
      result
    end

    # Emits one solid layer for *layer_glyph*, skipping empty outlines and
    # fully transparent colors.
    private def fill(atlas : Atlas, font : Font, layer_glyph : UInt32, color_index : UInt16,
                     palette : Array(StaticArray(Float32, 4))?, layers : LayerList) : Result
      begin
        outline = atlas.glyph(font, layer_glyph)
      rescue ex : Error
        return ex.result
      end
      return Result::Ok if outline.empty?
      color, foreground = resolve(palette, color_index)
      return Result::Ok unless color[3] > 0.0_f32
      layers.items << ColorLayer.new(outline: outline, transform: Affine.identity, color: color, foreground: foreground)
      Result::Ok
    end

    # Straight sRGB RGBA of a palette entry, alpha 1; *foreground* for 0xFFFF
    # and whenever the palette is unavailable (the style color applies then).
    private def resolve(palette : Array(StaticArray(Float32, 4))?, index : UInt16) : {StaticArray(Float32, 4), Bool}
      if index == 0xFFFF_u16 || palette.nil? || index.to_i >= palette.size
        return {StaticArray[0.0_f32, 0.0_f32, 0.0_f32, 1.0_f32], true}
      end
      {palette[index.to_i], false}
    end

    # The selected CPAL palette as straight sRGB floats with the font's
    # overrides applied; nil when unavailable (every layer falls back to the
    # foreground color).
    private def load_palette(font : Font, face : LibFT::Face*) : Array(StaticArray(Float32, 4))?
      state = font.color_state
      data = uninitialized LibFT::PaletteData
      return nil if LibFT.Slug_FT_Palette_Data_Get(face, pointerof(data)) != 0
      return nil if data.num_palettes == 0 || data.num_palette_entries == 0
      colors = Pointer(LibFT::Color).null
      return nil if LibFT.Slug_FT_Palette_Select(face, state.palette.to_u16, pointerof(colors)) != 0

      count = data.num_palette_entries.to_i
      palette = Array(StaticArray(Float32, 4)).new(count)
      count.times do |i|
        c = colors[i]
        palette << StaticArray[c.red.to_f32 / 255.0_f32, c.green.to_f32 / 255.0_f32,
          c.blue.to_f32 / 255.0_f32, c.alpha.to_f32 / 255.0_f32]
      end
      state.colors.each do |override|
        palette[override.index.to_i] = override.color
      end
      palette
    end
  end
end
