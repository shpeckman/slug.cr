# bench/gl.cr

require "../src/slug/gl"
require "../examples/egl"
require "../examples/frame"
require "./support"

options = SlugBench::Options.parse(gpu: true)
egl = DemoEGL.new(options.es)
font = Slug::Font.open(options.font)
renderer = Slug::GL::Renderer.new { |name| egl.get_proc(name) }
frame = DemoFrame.new(->egl.get_proc(UInt8*), options.width, options.height, true)
atlas = Slug::Atlas.new(Slug::AtlasDesc.new(initial_rows: 2_u32))
plain = SlugBench::Workload.emit(atlas, font, options.width, options.height)
effects = SlugBench::Workload.emit(atlas, font, options.width, options.height, effects: true)
renderer.sync(atlas)
plain_batch = renderer.create_batch(plain)
effects_batch = renderer.create_batch(effects)
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
  puts "backend: #{renderer.es? ? "OpenGL ES" : "OpenGL"}; persistent streaming: #{renderer.persistent_streaming?}"
  puts "viewport: #{options.width}x#{options.height}; instances: #{plain.size}; frames per sample: #{options.frames}"
  puts "samples: #{options.samples}; warmup: #{options.warmup}"
  SlugBench::Memory.atlas("GPU atlas", atlas)
  SlugBench::Memory.gpu_buffers(plain.size, effects.size, options.width, options.height)
  puts "GPU memory reports requested payload only; driver overhead is excluded"

  sync_atlas = atlas
  initial_sync_setup = -> {
    sync_atlas = Slug::Atlas.new(Slug::AtlasDesc.new(initial_rows: 2_u32))
    SlugBench::Workload.emit(sync_atlas, font, options.width, options.height)
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

  SlugBench.benchmark("retained plain", options, options.frames, "frames/s") do
    options.frames.times do
      frame.clear
      renderer.draw_batch(plain_batch, mvp, w, h)
    end
    finish.call
  end

  SlugBench.benchmark("streaming plain", options, options.frames, "frames/s") do
    options.frames.times do
      frame.clear
      renderer.draw(plain, mvp, w, h)
    end
    finish.call
  end

  SlugBench.benchmark("retained effects", options, options.frames, "frames/s") do
    options.frames.times do
      frame.clear
      renderer.draw_batch(effects_batch, mvp, w, h)
    end
    finish.call
  end

  SlugBench.benchmark("streaming effects", options, options.frames, "frames/s") do
    options.frames.times do
      frame.clear
      renderer.draw(effects, mvp, w, h)
    end
    finish.call
  end
  SlugBench::Memory.peak_rss
ensure
  renderer.destroy_batch(plain_batch)
  renderer.destroy_batch(effects_batch)
  font.close
  frame.close
  renderer.close
  egl.close
end
