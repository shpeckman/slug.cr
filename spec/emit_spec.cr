# spec/emit_spec.cr
require "./spec_helper"

describe Slug do
  font = Slug::Font.open("assets/unifont.ttf")
  atlas = Slug::Atlas.new

  after_each do
    atlas.clear
  end

  after_all do
    font.close
  end

  it "keeps the native instance layout at 84 bytes" do
    sizeof(Slug::Instance).should eq(84)
  end

  it "emits and measures empty text" do
    style = Slug::Style.new
    Slug.emit_text(atlas, font, style, "").should be_empty
    metrics = Slug.measure_text(atlas, font, "")
    metrics.lines.should eq(0)
    metrics.advance.should eq(0.0_f32)
    metrics.bounds.should eq(StaticArray[0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32])
  end

  it "shares line breaks and measurement with emission" do
    style = Slug::Style.new
    instances = Slug.emit_text(atlas, font, style, "A\nA")
    instances.size.should eq(2)
    instances[0].origin[0].should eq(instances[1].origin[0])
    instances[1].origin[1].should be < instances[0].origin[1]

    metrics = Slug.measure_text(atlas, font, "A\nA")
    metrics.lines.should eq(2)
    metrics.line_height.should eq(font.metrics.line_height)
    metrics.advance.should be > 0.0_f32
  end

  it "packs transforms, premultiplied color and effects" do
    color = StaticArray[0.8_f32, 0.6_f32, 0.4_f32, 0.5_f32]
    style = Slug::Style.new(
      transform: StaticArray[20.0_f32, 0.0_f32, 0.0_f32, 20.0_f32, 7.0_f32, 9.0_f32],
      color: color, optical_weight: true, dilation: 0.5_f32)
    instance = Slug.emit_text(atlas, font, style, "A").first
    instance.xform.should eq(StaticArray[20.0_f32, 0.0_f32, 0.0_f32, 20.0_f32])
    instance.origin[0].should eq(7.0_f32)
    instance.origin[1].should eq(9.0_f32)
    instance.col.should eq(StaticArray[0.4_f32, 0.3_f32, 0.2_f32, 0.5_f32])
    instance.dilation.should eq(0.5_f32)
    (instance.origin[3].unsafe_as(UInt32) & Slug::FLAG_WEIGHT).should_not eq(0)
  end

  it "emits placed glyphs" do
    glyph_id = Slug::LibFT.Slug_FT_Get_Char_Index(font.face.as(Void*), 'A'.ord)
    placement = Slug::Placement.new(glyph_id: glyph_id, x: 2.0_f32, y: 3.0_f32)
    instances = Slug.emit_glyphs(atlas, font, Slug::Style.new, [placement])
    instances.size.should eq(1)
    instances[0].origin[0].should eq(2.0_f32)
    instances[0].origin[1].should eq(3.0_f32)
  end

  it "rejects singular transforms and invalid effects" do
    singular = Slug::Style.new(transform: StaticArray[0.0_f32, 0.0_f32, 0.0_f32, 1.0_f32, 0.0_f32, 0.0_f32])
    expect_raises(Slug::Error) { Slug.emit_text(atlas, font, singular, "A") }
    invalid = Slug::Style.new(dilation: Float32::NAN)
    expect_raises(Slug::Error) { Slug.emit_text(atlas, font, invalid, "A") }
  end

  it "emits vector shapes and handles empty paths" do
    empty = atlas.add_path(Slug::Path.new)
    Slug.emit_shape(Slug::Style.new, empty).should be_nil
    path = Slug::Path.new
    path.move_to(0.0_f32, 0.0_f32).line_to(2.0_f32, 0.0_f32).line_to(0.0_f32, 2.0_f32)
    shape = atlas.add_path(path)
    style = Slug::Style.new(dilation: 1.0_f32)
    instance = Slug.emit_shape(style, shape).not_nil!
    instance.dilation.should eq(1.0_f32)
    instance.rect[2].should be > instance.rect[0]
  end
end
