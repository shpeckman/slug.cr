# slug

Native Crystal implementation of Slug text and vector rendering. FreeType outlines become curve and band atlases; the optional OpenGL renderer draws emitted instances directly on the GPU. No C Slug library is linked.

Features: UTF-8 text with kerning and line breaks, shaped glyph placement, measurement, TrueType/CFF outlines, COLRv0/CPAL color layers, vector paths, nonzero/even-odd fill, optical weight and dilation. COLRv1 paint graphs and advanced blend modes are not implemented.

Requirements: Crystal 1.22+ and FreeType. The renderer supports OpenGL 4.3 core and OpenGL ES 3.0+. The demo uses EGL by default, or GLFW with `--glfw`.

## Core

```crystal
require "slug"

font = Slug::Font.open("assets/unifont.ttf")
atlas = Slug::Atlas.new
style = Slug::Style.new(
  transform: StaticArray[32_f32, 0_f32, 0_f32, 32_f32, 100_f32, 200_f32],
  color: StaticArray[1_f32, 1_f32, 1_f32, 1_f32])
instances = Slug.emit_text(atlas, font, style, "Hello")
metrics = Slug.measure_text(atlas, font, "Hello")

# Later: font.close
```

Use `Slug.emit_glyphs` with `Slug::Placement` for HarfBuzz-style shaping. `Slug.emit_shape` emits a path stored with `Slug::Atlas#add_path`, which can grow it by *embolden* path units.

## OpenGL

```crystal
require "slug/gl"

renderer = Slug::GL::Renderer.new { |name| egl_get_proc_address(name) }
renderer.sync(atlas)
renderer.draw(instances, mvp, viewport_width.to_f32, viewport_height.to_f32)

batch = renderer.create_batch(instances)
renderer.draw_batch(batch, mvp, viewport_width.to_f32, viewport_height.to_f32)
renderer.draw_batch_range(batch, 0, 1, mvp, viewport_width.to_f32, viewport_height.to_f32)
```

The loader receives C function names as `UInt8*`. Create the renderer with the context current and use that same context for every call. `renderer.es?` and `renderer.persistent_streaming?` report backend behavior. Call `renderer.destroy_batch(batch)` and `renderer.close` during context teardown.

## Demo

```sh
crystal run examples/demo.cr
crystal run examples/demo.cr -- --es --output build/demo-es.ppm
crystal run examples/demo.cr -- assets/SGr-IosevkaTermSlab-Regular.ttc
crystal run examples/demo.cr -- --glfw --interactive
crystal run examples/demo.cr -- --stream --output build/demo-stream.ppm
```

The default demo creates a surfaceless EGL context and writes `build/demo.ppm`. `--output PATH` selects the image. `--es` selects GLES; `--glfw --interactive` keeps the window open. `--stream` uses fenced streaming instead of retained batch ranges. The demo covers text, measurement, effects, vector paths and fill rules.

## Benchmarks

Build optimized binaries before measuring:

```sh
devtool fs mkdir build
devtool cr build bench/core.cr --release -o build/bench-core
devtool cr build bench/gl.cr --release -o build/bench-gl
build/bench-core --workers 4
build/bench-gl
```

Or use the Makefile: `make build` builds both binaries, `make bench` runs the full suite, `make bench-core` and `make bench-gl` run one side, `make bench-ascii` runs the complex-font ASCII suite, and `make bench-gles` selects GLES. Set `BENCH_ARGS`, `CORE_ARGS`, `GL_ARGS`, `FONT` or `ASCII_FONT` to override workload options.

The core benchmark covers cold and batched atlas generation, warm emission, measurement and trimming, plus dense 100/500/1000/5000-glyph emission and measurement cases. The GPU benchmark uses surfaceless EGL and covers initial, incremental and no-op atlas synchronization plus retained and streaming draws with plain and effects shaders. It varies glyph counts at 16, 32 and 64 pixels, skipping combinations that exceed the viewport. Draw samples call `glFinish` after the requested frames so GPU work is included.

Use `--ascii` with a complex font to establish an ASCII baseline without unsupported Unicode glyphs:

```sh
build/bench-core --ascii --font assets/SGr-IosevkaTermSlab-Regular.ttc
build/bench-gl --ascii --font assets/SGr-IosevkaTermSlab-Regular.ttc
```

Both binaries accept `--font PATH`, `--ascii`, `--samples COUNT` and `--warmup COUNT`. The core binary also accepts `--workers COUNT`; the GPU binary accepts `--frames COUNT`, `--width PIXELS`, `--height PIXELS` and `--es`. Timing results include median, mean, p95, minimum, maximum and throughput.

Reports also include GC allocation and collection counts per measured operation, atlas used/allocated bytes, instance payloads and Linux peak RSS. Draw operations cover all frames in one sample. The core report shows atlas usage before and after trimming. GPU reports cover requested texture, retained-buffer, streaming-frame and framebuffer payload sizes; they exclude driver overhead and do not measure actual VRAM usage. Memory collection stays outside timed regions.
