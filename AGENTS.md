# Agent guide

Native Crystal Slug port. Core uses FreeType directly; no C Slug linkage. `src/slug.cr` loads the core, while `require "slug/gl"` opts into the renderer.

## Layout

- `src/slug/font.cr`: FreeType face, metrics, variations, palettes and outline styles.
- `src/slug/outline.cr`: outline capture/decomposition and half-float curve texels.
- `src/slug/bands.cr`: band selection and sorted curve references.
- `src/slug/atlas.cr`: curve/band planes, glyph and COLRv0 caches, paths, trimming.
- `src/slug/emit.cr`: shared text layout, instance emission and measurement.
- `src/slug/gl.cr`: dynamically loaded GL/GLES renderer, streaming and retained batches.
- `shaders/`: GL/GLES preludes, vertex shader, fragment shader and effects define.
- `examples/`: visual demo with surfaceless EGL or GLFW and PPM readback.
- `bench/`: release-mode core and EGL renderer benchmarks with shared timing, allocation and memory statistics.
- `spec/`: Crystal specs.
- `assets/`: bundled fonts and their licenses.

## Commands

```sh
devtool cr spec
devtool cr check src/slug.cr
devtool cr check src/slug/gl.cr
devtool cr docs
devtool cr run examples/demo.cr
devtool cr run examples/demo.cr -- --es --output build/demo-es.ppm
devtool cr run examples/demo.cr -- --glfw --output build/demo-glfw.ppm
devtool cr run examples/demo.cr -- --stream --output build/demo-stream.ppm
devtool fs mkdir build
devtool cr build bench/core.cr --release -o build/bench-core
devtool cr build bench/gl.cr --release -o build/bench-gl
build/bench-core --workers 4
build/bench-gl
make bench
make bench-ascii
make bench-gles
```

Use `LIBGL_ALWAYS_SOFTWARE=1` for llvmpipe. EGL uses Mesa's surfaceless platform. GLFW needs a display. Inspect generated images after changing shaders or rendering code.

## Invariants

- `Slug::Instance` is 84 bytes: five vec4 attributes followed by one float dilation attribute. Keep `types.cr`, `gl.cr` and vertex shader offsets aligned.
- Curve texels are RGBA16F and band texels RG16UI, 4096 texels wide. Both textures use nearest filtering.
- Packed band flags are defined in `types.cr`; optical weight is OR-ed in during emission.
- Plain and effects fragment variants share `slug.frag.glsl`; insert `effects.glsl` after the prelude for the effects variant.
- The renderer uploads only new atlas rows. Atlas ID changes replace textures; growth uses GPU copy when available and CPU re-upload otherwise.
- Persistent streaming fences every written range. Wait before reuse and on wrap. Retained batches own separate GL buffers.
- FreeType imports another shard may also declare use `Slug_FT_*` Crystal aliases and neutral `Void*` signatures; duplicate C imports must have identical signatures to coexist.
- `Slug::LibFT` is `:nodoc:` but shared: asekii-app loads, sizes and rasterizes its faces through it instead of declaring its own FreeType bindings, then hands faces to `Font.adopt` (`:nodoc:`; the font owns the face) and draws its registered glyphs with `Atlas#add_path`. Do not remove or change bindings without checking that user.
- Native scope is monochrome and COLRv0/CPAL. Do not copy C paint, clip or advanced-blend paths without porting their core representation too.
- Keep shader license notices and bundled font licenses intact.

## Standards

- Crystal 1.22+, compiler-friendly and idiomatic; every file starts with its path comment.
- Public APIs are ergonomic and documented. Internal types and extension points use `:nodoc:` or `private`.
- Avoid C-style output buffers in Crystal APIs; return arrays and values, raising `Slug::Error` on failure.
- Do not update the version in `shard.yml`.
- Keep README.md, this file and doc comments synchronized with behavior.
