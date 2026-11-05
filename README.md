# slug

Native Crystal implementation of Slug text and vector rendering. FreeType outlines become curve and band atlases; the optional OpenGL renderer draws emitted instances directly on the GPU. No C Slug library is linked.

Features: UTF-8 text with kerning and line breaks, shaped glyph placement, measurement, TrueType/CFF outlines, COLRv0/CPAL color layers, vector paths, nonzero/even-odd fill, optical weight, dilation and softness. COLRv1 paint graphs and advanced blend modes are not implemented.

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

Use `Slug.emit_glyphs` with `Slug::Placement` for HarfBuzz-style shaping. `Slug.emit_shape` emits a path stored with `Slug::Atlas#add_path`.

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
