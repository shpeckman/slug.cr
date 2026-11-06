# bench/support.cr

require "option_parser"
require "../src/slug"

module SlugBench
  class Options
    property font = "assets/unifont.ttf"
    property samples = 7
    property warmup = 2
    property workers = 1
    property frames = 30
    property width = 1280
    property height = 720
    property es = false

    def self.parse(gpu : Bool = false) : Options
      options = new
      parser = OptionParser.new do |parser|
        parser.banner = gpu ? "Usage: slug-bench-gl [options]" : "Usage: slug-bench-core [options]"
        parser.on("--font PATH", "Font file (default: #{options.font})") { |value| options.font = value }
        parser.on("--samples COUNT", "Measured samples per case (default: #{options.samples})") do |value|
          options.samples = positive(value, "--samples")
        end
        parser.on("--warmup COUNT", "Warmup iterations per case (default: #{options.warmup})") do |value|
          options.warmup = nonnegative(value, "--warmup")
        end
        unless gpu
          parser.on("--workers COUNT", "Atlas worker count (default: #{options.workers})") do |value|
            options.workers = positive(value, "--workers")
          end
        end
        if gpu
          parser.on("--frames COUNT", "Frames per draw sample (default: #{options.frames})") do |value|
            options.frames = positive(value, "--frames")
          end
          parser.on("--width PIXELS", "Viewport width (default: #{options.width})") do |value|
            options.width = positive(value, "--width")
          end
          parser.on("--height PIXELS", "Viewport height (default: #{options.height})") do |value|
            options.height = positive(value, "--height")
          end
          parser.on("--es", "Use OpenGL ES instead of desktop OpenGL") { options.es = true }
        end
        parser.on("-h", "--help", "Show this help") do
          puts parser
          exit
        end
      end
      parser.parse
      options
    end

    private def self.positive(value : String, option : String) : Int32
      number = value.to_i? || raise ArgumentError.new("#{option} needs an integer")
      raise ArgumentError.new("#{option} must be positive") unless number > 0
      number
    end

    private def self.nonnegative(value : String, option : String) : Int32
      number = value.to_i? || raise ArgumentError.new("#{option} needs an integer")
      raise ArgumentError.new("#{option} must not be negative") unless number >= 0
      number
    end
  end

  module Workload
    TEXT            = build_text
    CHARACTER_COUNT = TEXT.each_char.count { |char| char != '\n' }

    def self.build_text : String
      String.build do |output|
        output << "Slug native Crystal: Sphinx of black quartz, judge my vow 0123456789.\n"
        output << "GPU text directly from Bezier outlines; kerning, line breaks and effects.\n"
        column = 0
        {(32..126), (160..255), (0x391..0x3CE), (0x410..0x44F), (0x4E00..0x4E7F)}.each do |range|
          range.each do |codepoint|
            output << codepoint.chr
            column += 1
            if column == 72
              output << '\n'
              column = 0
            end
          end
        end
        output << '\n' unless column == 0
      end
    end

    def self.glyph_ids(font : Slug::Font) : Array(UInt32)
      bytes = TEXT.to_slice
      ids = [] of UInt32
      index = 0
      while index < bytes.size
        codepoint, index = Slug::UTF8.next(bytes, index)
        next if codepoint == '\n'.ord
        id = Slug::LibFT.Slug_FT_Get_Char_Index(font.face.as(Void*), codepoint)
        ids << id if id != 0 && !ids.includes?(id)
      end
      ids.sort!
    end

    def self.style(effects : Bool = false) : Slug::Style
      Slug::Style.new(
        transform: StaticArray[32.0_f32, 0.0_f32, 0.0_f32, 32.0_f32, 0.0_f32, 0.0_f32],
        color: StaticArray[0.92_f32, 0.94_f32, 1.0_f32, 1.0_f32],
        optical_weight: true,
        dilation: effects ? 0.25_f32 : 0.0_f32)
    end

    def self.emit(atlas : Slug::Atlas, font : Slug::Font, width : Int32, height : Int32,
                  effects : Bool = false) : Array(Slug::Instance)
      instances = [] of Slug::Instance
      size = Math.min(20, Math.max(8, width // 64))
      advance = size + 4
      TEXT.lines.each_with_index do |line, row|
        y = height - size - 8 - row * advance
        break if y < 0
        style = Slug::Style.new(
          transform: StaticArray[size.to_f32, 0.0_f32, 0.0_f32, size.to_f32, 16.0_f32, y.to_f32],
          color: StaticArray[0.92_f32, 0.94_f32, 1.0_f32, 1.0_f32],
          optical_weight: true,
          dilation: effects ? 0.25_f32 : 0.0_f32)
        instances.concat Slug.emit_text(atlas, font, style, line)
      end
      instances
    end

    def self.path : Slug::Path
      path = Slug::Path.new
      path.move_to(0.5_f32, 0.05_f32)
        .cubic_to(0.15_f32, 0.35_f32, 0.0_f32, 0.6_f32, 0.12_f32, 0.82_f32)
        .cubic_to(0.25_f32, 1.02_f32, 0.47_f32, 0.95_f32, 0.5_f32, 0.78_f32)
        .cubic_to(0.53_f32, 0.95_f32, 0.75_f32, 1.02_f32, 0.88_f32, 0.82_f32)
        .cubic_to(1.0_f32, 0.6_f32, 0.85_f32, 0.35_f32, 0.5_f32, 0.05_f32)
    end
  end

  def self.benchmark(name : String, options : Options, units : Int, rate : String,
                     setup : -> Nil = -> { }, &operation) : Nil
    options.warmup.times do
      setup.call
      operation.call
    end
    timings = Array(Float64).new(options.samples) do
      setup.call
      started = Time.instant
      operation.call
      (Time.instant - started).total_seconds
    end
    report(name, timings, units, rate)
  end

  private def self.report(name : String, timings : Array(Float64), units : Int, rate : String) : Nil
    sorted = timings.sort
    middle = sorted.size // 2
    median = sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) * 0.5
    mean = timings.sum / timings.size
    throughput = units / median
    printf "%-26s median %9.3f ms  mean %9.3f ms  min %9.3f ms  max %9.3f ms  %11.1f %s\n",
      name, median * 1000.0, mean * 1000.0, sorted.first * 1000.0, sorted.last * 1000.0, throughput, rate
  end
end
