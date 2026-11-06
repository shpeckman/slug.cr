# bench/core.cr

require "./support"

options = SlugBench::Options.parse
font = Slug::Font.open(options.font)
begin
  text = SlugBench::Workload::TEXT
  glyph_ids = SlugBench::Workload.glyph_ids(font)
  style = SlugBench::Workload.style
  warm_atlas = Slug::Atlas.new(Slug::AtlasDesc.new(initial_rows: 2_u32))
  warm_instances = Slug.emit_text(warm_atlas, font, style, text)
  trim_atlas = Slug::Atlas.new(Slug::AtlasDesc.new(initial_rows: 2_u32))
  trim_atlas.add_text(font, text)

  puts "font: #{options.font}"
  puts "workload: #{SlugBench::Workload::CHARACTER_COUNT} characters, #{glyph_ids.size} unique glyphs, #{warm_instances.size} instances"
  puts "samples: #{options.samples}; warmup: #{options.warmup}; workers: #{options.workers}"

  SlugBench.benchmark("cold emit", options, SlugBench::Workload::CHARACTER_COUNT, "glyphs/s") do
    atlas = Slug::Atlas.new(Slug::AtlasDesc.new(initial_rows: 2_u32))
    Slug.emit_text(atlas, font, style, text)
  end

  SlugBench.benchmark("batch atlas", options, glyph_ids.size, "glyphs/s") do
    atlas = Slug::Atlas.new(Slug::AtlasDesc.new(initial_rows: 2_u32))
    atlas.add_glyphs(font, glyph_ids, options.workers.to_u32)
  end

  SlugBench.benchmark("warm emit", options, SlugBench::Workload::CHARACTER_COUNT, "glyphs/s") do
    Slug.emit_text(warm_atlas, font, style, text)
  end

  SlugBench.benchmark("measure", options, SlugBench::Workload::CHARACTER_COUNT, "glyphs/s") do
    Slug.measure_text(warm_atlas, font, text)
  end

  trim_setup = -> {
    trim_atlas.add_text(font, text)
    trim_atlas.tick
    Slug.measure_text(trim_atlas, font, text.lines.first)
    nil
  }
  SlugBench.benchmark("atlas trim", options, 1, "trims/s", setup: trim_setup) do
    trim_atlas.trim
  end
ensure
  font.close
end
