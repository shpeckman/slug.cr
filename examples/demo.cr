# examples/demo.cr

require "../src/slug/gl"
require "./egl"
require "./glfw"
require "./frame"

class DemoScene
  @font : Slug::Font
  @atlas : Slug::Atlas
  @batch : Slug::GL::Batch
  @instances = [] of Slug::Instance

  def initialize(@renderer : Slug::GL::Renderer, font_path : String, @streamed : Bool)
    @font = Slug::Font.open(font_path)
    @atlas = Slug::Atlas.new(Slug::AtlasDesc.new(initial_rows: 2_u32))

    @instances.concat text("Slug · native Crystal", 48, 646, 34, rgb(0.92, 0.94, 1.0))
    @renderer.sync(@atlas)
    @instances.concat text("GPU text directly from Bézier outlines", 48, 604, 19, rgb(0.48, 0.67, 0.82))
    @instances.concat text("Sphinx of black quartz, judge my vow 0123456789", 48, 548, 25, rgb(0.90, 0.91, 0.93))
    @instances.concat text("Text measurement, kerning and\nmultiline layout share one walker.", 48, 452, 25, rgb(0.77, 0.82, 0.88))
    @instances.concat text("Bold + thin + optical weight", 48, 288, 24, rgb(0.82, 0.87, 0.94), dilation: 0.45_f32)
    @instances.concat text("Optical weight at small sizes", 48, 248, 14, rgb(0.68, 0.75, 0.84), optical: true)

    star = Slug::Path.new
    5.times do |i|
      angle = Math::PI * (0.5 + 0.8 * i)
      x = 0.5_f32 + 0.5_f32 * Math.cos(angle).to_f32
      y = 0.5_f32 + 0.5_f32 * Math.sin(angle).to_f32
      i == 0 ? star.move_to(x, y) : star.line_to(x, y)
    end
    nonzero = @atlas.add_path(star, Slug::FillRule::Nonzero)
    even_odd = @atlas.add_path(star, Slug::FillRule::EvenOdd)
    add_shape(@instances, nonzero, 810, 382, 178, rgb(0.91, 0.62, 0.24))
    add_shape(@instances, even_odd, 1010, 382, 178, rgb(0.35, 0.76, 0.88))

    heart = Slug::Path.new
    heart.move_to(0.5_f32, 0.05_f32)
      .cubic_to(0.15_f32, 0.35_f32, 0.0_f32, 0.6_f32, 0.12_f32, 0.82_f32)
      .cubic_to(0.25_f32, 1.02_f32, 0.47_f32, 0.95_f32, 0.5_f32, 0.78_f32)
      .cubic_to(0.53_f32, 0.95_f32, 0.75_f32, 1.02_f32, 0.88_f32, 0.82_f32)
      .cubic_to(1.0_f32, 0.6_f32, 0.85_f32, 0.35_f32, 0.5_f32, 0.05_f32)
    heart_shape = @atlas.add_path(heart)
    add_shape(@instances, heart_shape, 916, 142, 180, rgba(0.88, 0.24, 0.34, 0.9))

    @instances.concat text("nonzero", 842, 354, 16, rgb(0.70, 0.73, 0.79))
    @instances.concat text("even-odd", 1034, 354, 16, rgb(0.70, 0.73, 0.79))
    @instances.concat text("Vector paths · quadratic and cubic curves · fill rules · effects", 48, 72, 17, rgb(0.48, 0.58, 0.70))
    @instances.concat text("OpenGL 4.3 · no C Slug linkage", 48, 40, 14, rgb(0.38, 0.46, 0.56))

    metrics = Slug.measure_text(@atlas, @font, "Sphinx of black quartz, judge my vow 0123456789")
    puts "font: #{font_path}"
    puts "sample: #{metrics.advance} em wide, #{metrics.lines} line"
    puts "instances: #{@instances.size}"
    puts "curve texels: #{@atlas.curves.used}; band texels: #{@atlas.bands.used}"
    @renderer.sync(@atlas)
    @batch = @renderer.create_batch(@instances)
  end

  def draw(width : Int32, height : Int32) : Nil
    w = width.to_f32
    h = height.to_f32
    mvp = StaticArray[
      2.0_f32 / w, 0.0_f32, 0.0_f32, 0.0_f32,
      0.0_f32, 2.0_f32 / h, 0.0_f32, 0.0_f32,
      0.0_f32, 0.0_f32, 1.0_f32, 0.0_f32,
      -1.0_f32, -1.0_f32, 0.0_f32, 1.0_f32,
    ]
    if @streamed
      @renderer.draw(@instances, mvp, w, h)
    else
      split = @batch.count // 2
      @renderer.draw_batch_range(@batch, 0, split, mvp, w, h)
      @renderer.draw_batch_range(@batch, split, @batch.count - split, mvp, w, h)
    end
  end

  def close : Nil
    @renderer.destroy_batch(@batch)
    @font.close
  end

  private def text(value : String, x : Int32, y : Int32, size : Int32, color : StaticArray(Float32, 4),
                   dilation = 0.0_f32, optical = false) : Array(Slug::Instance)
    style = Slug::Style.new(
      transform: StaticArray[size.to_f32, 0.0_f32, 0.0_f32, size.to_f32, x.to_f32, y.to_f32],
      color: color, optical_weight: optical, dilation: dilation)
    Slug.emit_text(@atlas, @font, style, value)
  end

  private def add_shape(instances : Array(Slug::Instance), shape : Slug::Shape, x : Int32, y : Int32, size : Int32,
                        color : StaticArray(Float32, 4)) : Nil
    style = Slug::Style.new(
      transform: StaticArray[size.to_f32, 0.0_f32, 0.0_f32, size.to_f32, x.to_f32, y.to_f32],
      color: color)
    instances << Slug.emit_shape(style, shape).not_nil!
  end

  private def rgb(r : Float64, g : Float64, b : Float64) : StaticArray(Float32, 4)
    StaticArray[r.to_f32, g.to_f32, b.to_f32, 1.0_f32]
  end

  private def rgba(r : Float64, g : Float64, b : Float64, a : Float64) : StaticArray(Float32, 4)
    StaticArray[r.to_f32, g.to_f32, b.to_f32, a.to_f32]
  end
end

module Demo
  def self.capture(renderer : Slug::GL::Renderer, frame : DemoFrame, font : String, output : String,
                   width : Int32, height : Int32, streamed : Bool) : DemoScene
    scene = DemoScene.new(renderer, font, streamed)
    begin
      frame.clear
      scene.draw(width, height)
      frame.write_ppm(output)
      puts "wrote #{output}"
    rescue ex
      scene.close
      raise ex
    end
    scene
  end
end

use_glfw = false
interactive = false
streamed = false
output = "build/demo.ppm"
font = "assets/unifont.ttf"
index = 0
while index < ARGV.size
  case ARGV[index]
  when "--glfw"
    use_glfw = true
  when "--interactive"
    interactive = true
  when "--stream"
    streamed = true
  when "--output"
    index += 1
    raise "--output needs a path" if index >= ARGV.size
    output = ARGV[index]
  else
    font = ARGV[index]
  end
  index += 1
end
raise "--interactive requires --glfw" if interactive && !use_glfw

width = 1280
height = 720
if use_glfw
  window = DemoGLFW.new(width, height)
  begin
    renderer = Slug::GL::Renderer.new { |name| window.get_proc(name) }
    frame = DemoFrame.new(->window.get_proc(UInt8*), width, height, false)
    scene = Demo.capture(renderer, frame, font, output, width, height, streamed)
    begin
      if interactive
        while LibGLFW.glfwWindowShouldClose(window.window) == 0
          frame.clear
          window_width = 0_i32
          window_height = 0_i32
          LibGLFW.glfwGetFramebufferSize(window.window, pointerof(window_width), pointerof(window_height))
          unless window_width == 0 || window_height == 0
            scene.draw(window_width, window_height)
            LibGLFW.glfwSwapBuffers(window.window)
          end
          LibGLFW.glfwPollEvents
        end
      end
    ensure
      scene.close
      frame.close
      renderer.close
    end
  ensure
    window.close
  end
else
  egl = DemoEGL.new
  begin
    renderer = Slug::GL::Renderer.new { |name| egl.get_proc(name) }
    frame = DemoFrame.new(->egl.get_proc(UInt8*), width, height, true)
    scene = Demo.capture(renderer, frame, font, output, width, height, streamed)
    scene.close
    frame.close
    renderer.close
  ensure
    egl.close
  end
end
