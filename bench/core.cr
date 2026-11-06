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
  SlugBench::Memory.atlas("warm atlas", warm_atlas)
  SlugBench::Memory.instances("warm instances", warm_instances.size)

  cold_atlas = warm_atlas
  SlugBench.benchmark("cold emit", options, SlugBench::Workload::CHARACTER_COUNT, "glyphs/s") do
    cold_atlas = Slug::Atlas.new(Slug::AtlasDesc.new(initial_rows: 2_u32))
    Slug.emit_text(cold_atlas, font, style, text)
  end
  SlugBench::Memory.atlas("cold atlas", cold_atlas)

  batch_atlas = warm_atlas
  SlugBench.benchmark("batch atlas", options, glyph_ids.size, "glyphs/s") do
    batch_atlas = Slug::Atlas.new(Slug::AtlasDesc.new(initial_rows: 2_u32))
    batch_atlas.add_glyphs(font, glyph_ids, options.workers.to_u32)
  end
  SlugBench::Memory.atlas("batch atlas", batch_atlas)

  SlugBench.benchmark("warm emit", options, SlugBench::Workload::CHARACTER_COUNT, "glyphs/s") do
    Slug.emit_text(warm_atlas, font, style, text)
  end

  SlugBench.benchmark("measure", options, SlugBench::Workload::CHARACTER_COUNT, "glyphs/s") do
    Slug.measure_text(warm_atlas, font, text)
  end

  trim_before = SlugBench::Memory.atlas_usage(trim_atlas)
  trim_glyphs_after = SlugBench::Workload.glyph_ids(font, text.lines.first).size
  trim_setup = -> {
    trim_atlas.add_text(font, text)
    trim_before = SlugBench::Memory.atlas_usage(trim_atlas)
    trim_atlas.tick
    Slug.measure_text(trim_atlas, font, text.lines.first)
    nil
  }
  SlugBench.benchmark("atlas trim", options, 1, "trims/s", setup: trim_setup) do
    trim_atlas.trim
  end
  SlugBench::Memory.trim(trim_before, SlugBench::Memory.atlas_usage(trim_atlas), glyph_ids.size, trim_glyphs_after)
  SlugBench::Memory.peak_rss
ensure
  font.close
end
