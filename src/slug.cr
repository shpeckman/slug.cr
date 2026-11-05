# src/slug.cr
require "./slug/result"
require "./slug/error"
require "./slug/types"
require "./slug/half"
require "./slug/utf8"
require "./slug/affine"
require "./slug/font"
require "./slug/outline"
require "./slug/bands"
require "./slug/atlas"
require "./slug/path"
require "./slug/color"
require "./slug/emit"

# Slug turns font outlines and vector paths into curve and band textures
# consumed by the Slug shaders and emits one instance per drawn
# layer: one per monochrome glyph, one per layer of COLRv0/CPAL color glyphs.
# Native Crystal port of the C library, without any C Slug linkage.
#
# Coordinates: em space is font units divided by units-per-em, y up. Object
# space is em space mapped through `Style#transform`.
#
# The OpenGL 4.3 / GLES 3.0 renderer is opt-in: `require "slug/gl"`.
module Slug
  VERSION = "0.1.0"
end
