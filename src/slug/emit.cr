# src/slug/emit.cr

require "./atlas"
require "./path"

module Slug
  # :nodoc:
  struct Layout
    getter advance : Float32
    getter lines : UInt32

    def initialize(@advance : Float32, @lines : UInt32)
    end
  end

  # :nodoc:
  class Emitter
    getter instances : Array(Instance)

    @m : Affine
    @color : StaticArray(Float32, 4)
    @flags : UInt32

    def initialize(@atlas : Atlas?, @font : Font?, style : Style, capacity : Int)
      x = style.transform
      det = x[0] * x[3] - x[2] * x[1]
      unless det.abs > 0.0_f32 && det.finite? && style.dilation.finite?
        raise Error.new(Result::InvalidArgument)
      end

      @m = Affine.new(x[0], x[1], x[2], x[3], x[4], x[5])
      a = style.color[3]
      @color = StaticArray[style.color[0] * a, style.color[1] * a, style.color[2] * a, a]
      @flags = style.optical_weight? ? FLAG_WEIGHT : 0_u32
      @dilation = style.dilation
      @monochrome = style.monochrome?
      @instances = Array(Instance).new(capacity)
    end

    def glyph(glyph_id : UInt32, glyph : Glyph, px : Float32, py : Float32) : Nil
      placed = @m * Affine.new(1.0_f32, 0.0_f32, 0.0_f32, 1.0_f32, px, py)
      font = @font.not_nil!
      unless @monochrome || font.metrics.color_format.none?
        color, layers = @atlas.not_nil!.color(font, glyph_id)
        layers.each do |layer|
          c = if layer.foreground?
                a = layer.color[3]
                StaticArray[@color[0] * a, @color[1] * a, @color[2] * a, @color[3] * a]
              else
                a = layer.color[3] * @color[3]
                StaticArray[layer.color[0] * a, layer.color[1] * a, layer.color[2] * a, a]
              end
          put(layer.outline, placed * layer.transform, c)
        end
        return if color.color?
      end
      put(glyph, placed, @color) unless glyph.empty?
    end

    def shape(shape : Shape) : Nil
      return if shape.glyph.empty?
      unit = Affine.new(shape.scale, 0.0_f32, 0.0_f32, shape.scale, shape.origin[0], shape.origin[1])
      put(shape.glyph, @m * unit, @color)
    end

    private def put(glyph : Glyph, m : Affine, color : StaticArray(Float32, 4)) : Nil
      @instances << Instance.new(
        rect: glyph.bounds,
        xform: StaticArray[m.a, m.b, m.c, m.d],
        origin: StaticArray[m.e, m.f, glyph.location.unsafe_as(Float32), (glyph.band_info | @flags).unsafe_as(Float32)],
        bnd: StaticArray[glyph.band_scale[0], glyph.band_scale[1], glyph.band_offset[0], glyph.band_offset[1]],
        col: color,
        dilation: @dilation)
    end
  end

  # Emits one instance per visible outline in *text*, including each color layer.
  #
  # The style transform maps em coordinates to object coordinates. Raises
  # `Error` when the transform is singular, an effect is invalid, or the atlas
  # cannot supply a glyph.
  def self.emit_text(atlas : Atlas, font : Font, style : Style, text : String) : Array(Instance)
    emit_text(atlas, font, style, text.to_slice, text.size)
  end

  # :ditto:
  def self.emit_text(atlas : Atlas, font : Font, style : Style, text : Bytes) : Array(Instance)
    emit_text(atlas, font, style, text, UTF8.count(text))
  end

  private def self.emit_text(atlas : Atlas, font : Font, style : Style, text : Bytes, capacity : Int) : Array(Instance)
    emitter = Emitter.new(atlas, font, style, capacity)
    walk_text(atlas, font, text) do |glyph_id, glyph, x, y|
      emitter.glyph(glyph_id, glyph, x, y)
    end
    emitter.instances
  end

  # Emits placed glyph IDs, for example from a text shaper.
  #
  # Placement coordinates are in em units before `Style#transform` is applied.
  def self.emit_glyphs(atlas : Atlas, font : Font, style : Style, glyphs : Indexable(Placement)) : Array(Instance)
    emitter = Emitter.new(atlas, font, style, glyphs.size)
    glyphs.each do |placement|
      glyph = atlas.glyph(font, placement.glyph_id)
      emitter.glyph(placement.glyph_id, glyph, placement.x, placement.y)
    end
    emitter.instances
  end

  # Emits *shape*, or returns nil for an empty shape.
  def self.emit_shape(style : Style, shape : Shape) : Instance?
    emitter = Emitter.new(nil, nil, style, 1)
    emitter.shape(shape)
    emitter.instances[0]?
  end

  # Measures *text* in em units, including kerning, line breaks and color bounds.
  def self.measure_text(atlas : Atlas, font : Font, text : String) : TextMetrics
    measure_text(atlas, font, text.to_slice)
  end

  # :ditto:
  def self.measure_text(atlas : Atlas, font : Font, text : Bytes) : TextMetrics
    bounds = StaticArray[0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32]
    ink = false
    layout = walk_text(atlas, font, text) do |glyph_id, glyph, x, y|
      if font.metrics.color_format.none?
        next if glyph.empty?
        box = glyph.bounds
      else
        color, _ = atlas.color(font, glyph_id)
        next if color.color? ? color.count == 0 : glyph.empty?
        box = color.color? ? color.bounds : glyph.bounds
      end
      if ink
        bounds[0] = Math.min(bounds[0], box[0] + x)
        bounds[1] = Math.min(bounds[1], box[1] + y)
        bounds[2] = Math.max(bounds[2], box[2] + x)
        bounds[3] = Math.max(bounds[3], box[3] + y)
      else
        bounds = StaticArray[box[0] + x, box[1] + y, box[2] + x, box[3] + y]
        ink = true
      end
    end
    TextMetrics.new(layout.advance, bounds, layout.lines, font.metrics.line_height)
  end

  private def self.walk_text(atlas : Atlas, font : Font, text : Bytes, &) : Layout
    face = font.face
    kerning = (face.value.face_flags & LibFT::FACE_FLAG_KERNING) != 0
    scale = 1.0_f32 / face.value.units_per_em.to_f32
    x = 0.0_f32
    y = 0.0_f32
    previous = 0_u32
    advance = 0.0_f32
    lines = text.empty? ? 0_u32 : 1_u32
    index = 0

    while index < text.size
      codepoint, index = UTF8.next(text, index)
      if codepoint == '\n'.ord
        advance = Math.max(advance, x)
        lines &+= 1
        x = 0.0_f32
        y -= font.metrics.line_height
        previous = 0_u32
        next
      end

      glyph_id = LibFT.Slug_FT_Get_Char_Index(face.as(Void*), codepoint)
      if kerning && previous != 0
        kern = LibFT::Vector.new
        if LibFT.Slug_FT_Get_Kerning(face, previous, glyph_id, LibFT::KERNING_UNSCALED.to_u32, pointerof(kern)) == 0
          x += kern.x.to_f32 * scale
        end
      end

      glyph = atlas.glyph(font, glyph_id)
      yield glyph_id, glyph, x, y
      x += glyph.advance
      previous = glyph_id
    end
    Layout.new(Math.max(advance, x), lines)
  end
end
