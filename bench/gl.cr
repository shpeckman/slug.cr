# bench/gl.cr

require "../src/slug/gl"
require "../examples/egl"
require "../examples/frame"
require "./support"

options = SlugBench::Options.parse(gpu: true)
egl = DemoEGL.new
font = Slug::Font.open(options.font)
renderer = Slug::GL::Renderer.new { |name| egl.get_proc(name) }
frame = DemoFrame.new(->egl.get_proc(UInt8*), options.width, options.height, true)
atlas = Slug::Atlas.new(Slug::AtlasDesc.new(initial_rows: 2_u32))
base_text = SlugBench::Workload.base_text(options.ascii)
scene_data = [] of Tuple(Int32, Int32, Array(Slug::Instance), Array(Slug::Instance))
SlugBench::Workload::SIZES.each do |size|
  SlugBench::Workload::GLYPH_COUNTS.each do |count|
    next if count > SlugBench::Workload.grid_capacity(options.width, options.height, size)
    plain = SlugBench::Workload.emit_grid(atlas, font, options.width, options.height, count, size, options.ascii)
    effects = SlugBench::Workload.emit_grid(atlas, font, options.width, options.height, count, size, options.ascii, effects: true)
    scene_data << {count, size, plain, effects}
  end
end
renderer.sync(atlas)
scenes = scene_data.map do |count, size, plain, effects|
  {count: count, size: size, plain: plain, effects: effects,
   plain_batch: renderer.create_batch(plain), effects_batch: renderer.create_batch(effects)}
end
begin
  finish_address = egl.get_proc("glFinish".to_unsafe)
  raise "OpenGL: missing glFinish" if finish_address.null?
  finish = Proc(Nil).new(finish_address, Pointer(Void).null)
  w = options.width.to_f32
  h = options.height.to_f32
  mvp = StaticArray[
    2.0_f32 / w, 0.0_f32, 0.0_f32, 0.0_f32,
    0.0_f32, 2.0_f32 / h, 0.0_f32, 0.0_f32,
    0.0_f32, 0.0_f32, 1.0_f32, 0.0_f32,
    -1.0_f32, -1.0_f32, 0.0_f32, 1.0_f32,
  ]

  puts "font: #{options.font}"
  puts "workload: #{options.ascii ? "ASCII" : "Unicode"}; scenes: #{scenes.size}"
  puts "persistent streaming: #{renderer.persistent_streaming?}"
  puts "viewport: #{options.width}x#{options.height}; frames per sample: #{options.frames}"
  puts "samples: #{options.samples}; warmup: #{options.warmup}"
  scenes.each { |scene| SlugBench::Memory.instances("plain #{scene[:count]}@#{scene[:size]}", scene[:plain].size) }
  SlugBench::Memory.atlas("GPU atlas", atlas)
  SlugBench::Memory.gpu_buffers(scenes.map { |scene| scene[:plain].size }, scenes.map { |scene| scene[:effects].size }, options.width, options.height)
  puts "GPU memory reports requested payload only; driver overhead is excluded"

  sync_atlas = atlas
  initial_sync_setup = -> {
    sync_atlas = Slug::Atlas.new(Slug::AtlasDesc.new(initial_rows: 2_u32))
    SlugBench::Workload.emit(sync_atlas, font, options.width, options.height, text: base_text)
    nil
  }
  SlugBench.benchmark("initial sync", options, 1, "syncs/s", setup: initial_sync_setup) do
    renderer.sync(sync_atlas)
    finish.call
  end

  renderer.sync(atlas)
  incremental_sync_setup = -> {
    atlas.add_path(SlugBench::Workload.path)
    nil
  }
  SlugBench.benchmark("incremental sync", options, 1, "syncs/s", setup: incremental_sync_setup) do
    renderer.sync(atlas)
    finish.call
  end

  SlugBench.benchmark("no-op sync", options, 1, "syncs/s") do
    renderer.sync(atlas)
    finish.call
  end

  scenes.each do |scene|
    count = scene[:count]
    size = scene[:size]
    plain = scene[:plain]
    effects = scene[:effects]
    plain_batch = scene[:plain_batch]
    effects_batch = scene[:effects_batch]
    label = "#{count}@#{size}"

    SlugBench.benchmark("retained plain #{label}", options, options.frames, "frames/s") do
      options.frames.times do
        frame.clear
        renderer.draw_batch(plain_batch, mvp, w, h)
      end
      finish.call
    end

    SlugBench.benchmark("streaming plain #{label}", options, options.frames, "frames/s") do
      options.frames.times do
        frame.clear
        renderer.draw(plain, mvp, w, h)
      end
      finish.call
    end

    SlugBench.benchmark("retained fx #{label}", options, options.frames, "frames/s") do
      options.frames.times do
        frame.clear
        renderer.draw_batch(effects_batch, mvp, w, h)
      end
      finish.call
    end

    SlugBench.benchmark("streaming fx #{label}", options, options.frames, "frames/s") do
      options.frames.times do
        frame.clear
        renderer.draw(effects, mvp, w, h)
      end
      finish.call
    end
  end
  SlugBench::Memory.peak_rss
ensure
  scenes.each do |scene|
    renderer.destroy_batch(scene[:plain_batch])
    renderer.destroy_batch(scene[:effects_batch])
  end
  font.close
  frame.close
  renderer.close
  egl.close
end
