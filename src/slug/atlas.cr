# src/slug/atlas.cr

require "./result"
require "./error"
require "./types"
require "./lib_ft"
require "./utf8"
require "./color"

module Slug
  # Curve and band texture storage shared by any number of fonts and paths.
  #
  # The atlas only appends: every glyph, color glyph layer and path is placed
  # once, and the `#curves` and `#bands` plane views describe the atlas until
  # its next mutation. `#clear` and `#trim` are the only resets; both assign a
  # new `#id` so backends replace their textures.
  #
  # Glyphs are cached per font variation and outline style, color glyphs per
  # palette, so switching either is cheap after first use.
  class Atlas
    # :nodoc: glyphs per load/band/place round in `#add_glyphs`
    private JOB_CHUNK = 512

    # :nodoc: `TEXTURE_WIDTH` as UInt64 for texel address arithmetic
    private W64 = TEXTURE_WIDTH.to_u64

    @@next_id = Atomic(UInt64).new(1_u64)

    # :nodoc:
    #
    # Open-addressing map from 64-bit keys to nonzero 32-bit values
    # (power-of-two capacity, load factor at or below one half).
    private class Table
      @keys = [] of UInt64
      @slots = [] of UInt32 # 0 = empty
      @count = 0

      def get(key : UInt64) : UInt32
        cap = @slots.size
        return 0_u32 if cap == 0
        mask = cap - 1
        i = (Table.hash(key) & mask.to_u64).to_i
        loop do
          slot = @slots[i]
          return 0_u32 if slot == 0
          return slot if @keys[i] == key
          i = (i + 1) & mask
        end
      end

      # Inserts a key not yet present.
      def set(key : UInt64, value : UInt32) : Nil
        grow if (@count + 1) * 2 > @slots.size
        Table.put(@keys, @slots, key, value)
        @count += 1
      end

      def clear : Nil
        @slots.fill(0_u32)
        @count = 0
      end

      # Every stored key, indexed by value - 1 (the inverse of the map).
      def keys_by_index(count : Int) : Array(UInt64)
        keys = Array(UInt64).new(count, 0_u64)
        @slots.size.times do |i|
          slot = @slots[i]
          keys[slot - 1] = @keys[i] if slot != 0
        end
        keys
      end

      def self.hash(k : UInt64) : UInt64
        k &+= 0x9E3779B97F4A7C15_u64
        k = (k ^ (k >> 30)) &* 0xBF58476D1CE4E5B9_u64
        k = (k ^ (k >> 27)) &* 0x94D049BB133111EB_u64
        k ^ (k >> 31)
      end

      def self.put(keys : Array(UInt64), slots : Array(UInt32), key : UInt64, value : UInt32) : Nil
        mask = slots.size - 1
        i = (hash(key) & mask.to_u64).to_i
        while slots[i] != 0
          i = (i + 1) & mask
        end
        keys[i] = key
        slots[i] = value
      end

      private def grow : Nil
        cap = @slots.size == 0 ? 64 : @slots.size * 2
        keys = Array(UInt64).new(cap, 0_u64)
        slots = Array(UInt32).new(cap, 0_u32)
        @slots.size.times do |i|
          Table.put(keys, slots, @keys[i], @slots[i]) if @slots[i] != 0
        end
        @keys = keys
        @slots = slots
      end
    end

    # :nodoc:
    #
    # Append-only texel plane; writes stay contiguous within one row of
    # `TEXTURE_WIDTH` texels because the shaders index without wrapping.
    private class PlaneData
      getter data : Bytes
      getter rows : UInt32
      getter texel_size : UInt32
      property used : UInt64

      def initialize(rows : UInt32, @texel_size : UInt32)
        @rows = rows
        @data = Bytes.new(rows.to_i64 * TEXTURE_WIDTH.to_i64 * @texel_size.to_i64)
        @used = 0_u64
      end

      # Raw pointer of the texel at the linear *address*.
      def texel(address : UInt64) : UInt8*
        @data.to_unsafe + address * @texel_size.to_u64
      end

      def resize(rows : UInt32) : Nil
        return if rows == @rows
        data = Bytes.new(rows.to_i64 * TEXTURE_WIDTH.to_i64 * @texel_size.to_i64)
        data.copy_from(@data[0, Math.min(data.size, @data.size)])
        @data = data
        @rows = rows
      end

      # Grows (doubling) until *texels* fit; `Result::Limit` past `MAX_ROWS`.
      def reserve(texels : UInt64) : Result
        need = (texels &+ (W64 - 1)) // W64
        return Result::Limit if need > MAX_ROWS
        return Result::Ok if need <= @rows
        rows = @rows.to_u64
        while rows < need
          rows *= 2
        end
        rows = MAX_ROWS.to_u64 if rows > MAX_ROWS
        resize(rows.to_u32)
        Result::Ok
      end

      # Zeroes the rows in use and rewinds; capacity is kept.
      def clear_used : Nil
        rows = (@used &+ (W64 - 1)) // W64
        @data.to_unsafe.clear((rows * W64 * @texel_size.to_u64).to_i)
        @used = 0_u64
      end
    end

    # :nodoc:
    #
    # One glyph moving through the build phases: load (FreeType, calling
    # fiber), band (pure computation, worker fibers), place (calling fiber).
    private class Job
      property glyph_id = 0_u32
      property key = 0_u64
      property outline = Outline.new
      property bands = Bands.new
      property result = Result::Ok
      property empty = false
    end

    # :nodoc: texel ranges of one placed outline (glyph or path), so `#trim` can move it
    private struct Span
      getter curve_start : UInt64
      getter curve_end : UInt64
      getter band_start : UInt64
      getter band_end : UInt64
      getter header : UInt32

      def initialize(@curve_start : UInt64, @curve_end : UInt64, @band_start : UInt64, @band_end : UInt64,
                     @header : UInt32)
      end
    end

    # :nodoc: every placed outline, keyed by packed band location
    private class Spans
      getter items = [] of Span
      getter table = Table.new

      def add(location : UInt32, span : Span) : Nil
        @table.set(location.to_u64, @items.size.to_u32 &+ 1)
        @items << span
      end

      def clear : Nil
        @items.clear
        @table.clear
      end
    end

    # :nodoc: a run of texels copied from one plane to another; runs never straddle a row in either plane
    private record Piece, from : UInt64, to : UInt64, len : UInt64

    # :nodoc: state of one trim, swapped into the atlas only when every step succeeded
    private class Trim
      getter curves : PlaneData
      getter bands : PlaneData
      getter spans = Spans.new
      getter moved = Table.new # old packed location -> index + 1 into `locations`
      getter old_locations = [] of UInt32
      getter locations = [] of UInt32
      getter curve_pieces = [] of Piece
      getter band_pieces = [] of Piece
      getter glyphs = [] of Glyph
      getter glyph_use = [] of UInt32
      getter glyph_table = Table.new
      getter colors = [] of ColorGlyph
      getter color_use = [] of UInt32
      getter color_table = Table.new
      getter layers = [] of ColorLayer

      def initialize(curve_rows : UInt32, band_rows : UInt32)
        @curves = PlaneData.new(curve_rows, 8_u32)
        @bands = PlaneData.new(band_rows, 4_u32)
      end
    end

    @curves : PlaneData
    @bands : PlaneData
    @max_bands : UInt32
    @cubic_tolerance : Float32
    @band_slack : Float32
    @frozen = false
    @id : UInt64
    @glyph_table = Table.new
    @spans = Spans.new
    @color_table = Table.new
    @scratch_layers = LayerList.new
    @scratch = Job.new

    # Creates an atlas configured by *desc*.
    #
    # Fields left at their `AtlasDesc` defaults (or zero) take the documented
    # defaults. Raises `Error` with `Result::InvalidArgument` for values out
    # of range.
    def initialize(desc : AtlasDesc = AtlasDesc.new)
      initial_rows = desc.initial_rows
      initial_rows = 64_u32 if initial_rows == 0
      max_bands = desc.max_bands
      max_bands = 16_u32 if max_bands == 0
      cubic_tolerance = desc.cubic_tolerance
      cubic_tolerance = 1.0_f32 / 2048.0_f32 if cubic_tolerance <= 0.0_f32
      if initial_rows > MAX_ROWS || max_bands > MAX_BANDS || !(desc.band_slack >= 0.0_f32)
        raise Error.new(Result::InvalidArgument)
      end

      @max_bands = max_bands
      @cubic_tolerance = cubic_tolerance
      @band_slack = desc.band_slack
      @id = Atlas.next_id
      @curves = PlaneData.new(initial_rows, 8_u32)
      @bands = PlaneData.new(initial_rows, 4_u32)
      @glyphs = [] of Glyph
      @glyph_use = [] of UInt32
      @colors = [] of ColorGlyph
      @color_use = [] of UInt32
      @layers = [] of ColorLayer
      @collected = [] of UInt32
      @jobs = [] of Job
      @curve_loc = [] of UInt32
      @seg_addr = [] of UInt64
      @period = 0_u32
    end

    # :nodoc: process-unique identifier source
    def self.next_id : UInt64
      @@next_id.add(1_u64)
    end

    # Looks up a glyph outline, adding it on first use. For color glyphs this
    # is the monochrome fallback outline; their layers are added on emission.
    #
    # Raises `Error` with `Result::Frozen` for a missing glyph once the atlas
    # is frozen.
    def glyph(font : Font, glyph_id : UInt32) : Glyph
      key = glyph_key(font, glyph_id)
      found = lookup(key)
      return found if found
      raise Error.new(Result::Frozen) if @frozen

      job = @scratch
      job.glyph_id = glyph_id
      load_job(font, job)
      band_job(job)
      result, glyph = place_job(job)
      Slug.check(result)
      insert(key, glyph)
      glyph
    end

    # Adds many glyphs in one call, e.g. to warm an atlas before freezing it.
    # Color glyphs of the selected palette are added with all their layers.
    #
    # Outlines load on the calling fiber (FreeType faces are not
    # thread-safe); band construction, the larger part of the work, runs on
    # *threads* workers (values <= 1 use the calling fiber only); placement is
    # deterministic and independent of the worker count. Present and repeated
    # glyphs are skipped. On error, glyphs listed before the failing one may
    # already be added.
    def add_glyphs(font : Font, glyph_ids : Indexable(UInt32), threads : UInt32 = 1_u32) : Nil
      add_outlines(font, glyph_ids, threads)
      return if font.metrics.color_format.none?

      # Color glyphs: build all layer outlines in parallel, then the (cheap, serial) color records.
      @collected.clear
      glyph_ids.each do |glyph_id|
        Slug.check(Color.build(self, font, glyph_id, nil, @collected))
      end
      add_outlines(font, @collected, threads)
      glyph_ids.each { |glyph_id| color(font, glyph_id) }
      nil
    end

    # Adds every glyph mapped by the UTF-8 *text*; newlines are skipped.
    def add_text(font : Font, text : String) : Nil
      add_text(font, text.to_slice)
    end

    # :ditto:
    def add_text(font : Font, text : Bytes) : Nil
      index = 0
      while index < text.size
        codepoint, index = UTF8.next(text, index)
        next if codepoint == '\n'.ord
        glyph_id = LibFT.FT_Get_Char_Index(font.face, codepoint)
        glyph(font, glyph_id)
        color(font, glyph_id)
      end
    end

    # Stores a path's fill in the atlas. Paths are not cached by identity:
    # call once and keep the shape.
    #
    # Raises `Error` with `Result::Frozen` in a frozen atlas; an empty path
    # yields an empty shape.
    def add_path(path : Path, fill : FillRule = :nonzero) : Shape
      raise Error.new(Result::Frozen) if @frozen

      job = @scratch
      result, origin, scale = job.outline.from_path(path, fill)
      job.result = result
      job.empty = result.unsupported?
      job.result = Result::Ok if job.empty
      band_job(job)
      result, glyph = place_job(job)
      Slug.check(result)
      Shape.new(glyph, origin, scale)
    end

    # Freezes the atlas: no glyphs can be added afterwards (static mode).
    # With *shrink* the textures are trimmed to the rows in use.
    def freeze(shrink : Bool = false) : Nil
      @frozen = true
      return unless shrink

      {@curves, @bands}.each do |plane|
        rows = ((plane.used &+ (W64 - 1)) // W64).to_u32
        rows = 1_u32 if rows == 0
        plane.resize(rows) if rows < plane.rows
      end
    end

    # Removes every glyph, color glyph and shape and unfreezes the atlas;
    # texture capacity is kept. The atlas gets a new `#id`, so backends
    # replace their textures on the next sync. Use it to bound memory in
    # long-running programs, then re-emit the text that is still visible.
    def clear : Nil
      @curves.clear_used
      @bands.clear_used
      @glyph_table.clear
      @color_table.clear
      @spans.clear
      @glyphs.clear
      @glyph_use.clear
      @colors.clear
      @color_use.clear
      @layers.clear
      @frozen = false
      @id = Atlas.next_id
    end

    # Returns true when the atlas is frozen.
    def frozen? : Bool
      @frozen
    end

    # Starts a new use period for `#trim`, typically once per frame. Glyphs
    # and color glyphs record the period of their last use (emission,
    # measurement, `#glyph`, `#add_glyphs` and the like).
    def tick : Nil
      @period &+= 1
    end

    # Removes glyphs and color glyphs not used in the last *periods* periods
    # (0 keeps only those used since the last `#tick`) and compacts the
    # textures; capacity is kept. Kept glyphs are moved, not rebuilt, so their
    # fonts need not be alive. Like `#clear`, the atlas gets a new `#id`:
    # instances emitted earlier and every `Shape` become invalid, so re-emit
    # (and re-add paths) afterwards.
    #
    # Raises `Error` with `Result::Frozen` on a frozen atlas; on any other
    # failure the atlas is unchanged.
    def trim(periods : UInt32 = 0_u32) : Nil
      raise Error.new(Result::Frozen) if @frozen

      t = Trim.new(@curves.rows, @bands.rows)
      glyph_keys = @glyph_table.keys_by_index(@glyphs.size)
      color_keys = @color_table.keys_by_index(@colors.size)

      # Outlines to keep: recently used glyphs, and every outline of recently used color glyphs.
      @colors.each_with_index do |cg, c|
        next if @period &- @color_use[c] > periods
        cg.count.times do |i|
          layer = @layers[cg.first.to_i + i]
          keep_location(t, layer.outline.location) unless layer.outline.empty?
        end
      end
      @glyphs.each_with_index do |g, gi|
        next if g.empty? || @period &- @glyph_use[gi] > periods
        keep_location(t, g.location)
      end

      # Move them in their old order, which keeps the layout of glyphs built together.
      t.old_locations.sort_by! { |location| unpack_location(location) }
      t.moved.clear
      t.old_locations.each do |location|
        t.moved.set(location.to_u64, t.locations.size.to_u32 &+ 1)
        result, new_location = move_outline(t, location)
        Slug.check(result)
        t.locations << new_location
      end

      # Glyph table: recently used glyphs and the outlines kept for color glyphs, in their old order.
      @glyphs.each_with_index do |g, gi|
        glyph = g
        recent = @period &- @glyph_use[gi] <= periods
        kept = glyph.empty? ? recent : t.moved.get(glyph.location.to_u64) != 0
        next unless kept
        glyph.location = moved_location(t, glyph.location) unless glyph.empty?
        t.glyph_table.set(glyph_keys[gi], t.glyphs.size.to_u32 &+ 1)
        t.glyph_use << @glyph_use[gi]
        t.glyphs << glyph
      end

      # Color glyphs: layers with moved outlines.
      @colors.each_with_index do |cg, c|
        next if @period &- @color_use[c] > periods
        color = cg
        first = t.layers.size.to_u32
        cg.count.times do |i|
          layer = @layers[cg.first.to_i + i]
          layer.outline.location = moved_location(t, layer.outline.location) unless layer.outline.empty?
          t.layers << layer
        end
        color.first = first
        t.color_table.set(color_keys[c], t.colors.size.to_u32 &+ 1)
        t.color_use << @color_use[c]
        t.colors << color
      end

      # Swap the trimmed state in; the old state is garbage-collected.
      @curves = t.curves
      @bands = t.bands
      @spans = t.spans
      @glyphs = t.glyphs
      @glyph_use = t.glyph_use
      @glyph_table = t.glyph_table
      @colors = t.colors
      @color_use = t.color_use
      @color_table = t.color_table
      @layers = t.layers
      @id = Atlas.next_id
      nil
    end

    # Returns a view of the curve texture (RGBA16F, 8 bytes per texel).
    #
    # The view is a snapshot taken now: the bytes stay readable, but they
    # describe the atlas only until its next mutation.
    def curves : Plane
      view(@curves)
    end

    # Returns a view of the band texture (RG16UI, 4 bytes per texel).
    # Snapshot semantics as `#curves`.
    def bands : Plane
      view(@bands)
    end

    # Returns the process-unique identifier of the atlas, changed by `#clear`
    # and `#trim` so backends replace their textures on the next sync.
    def id : UInt64
      @id
    end

    # :nodoc:
    #
    # Cached color expansion of *glyph_id* for the font's current palette: the
    # `ColorGlyph` and a copy of its layers. `ColorGlyph#color?` is false for
    # monochrome glyphs; a color glyph with zero layers (fully transparent)
    # draws nothing. Used by emission and by `#add_text` / `#add_glyphs`.
    def color(font : Font, glyph_id : UInt32) : {ColorGlyph, Array(ColorLayer)}
      empty = {ColorGlyph.new, [] of ColorLayer}
      return empty if font.metrics.color_format.none? || glyph_id > 0xFFFF_u32

      key = color_key(font, glyph_id)
      slot = @color_table.get(key)
      if slot == 0
        if @frozen
          # Uncached in a frozen atlas: an error only when it really is a color glyph.
          @collected.clear
          Slug.check(Color.build(self, font, glyph_id, nil, @collected))
          raise Error.new(Result::Frozen) unless @collected.empty?
          return empty
        end
        list = @scratch_layers
        list.clear
        Slug.check(Color.build(self, font, glyph_id, list, nil))

        glyph = ColorGlyph.new(first: @layers.size.to_u32, count: list.items.size.to_u32, color: list.color?)
        bounds = StaticArray[Float32::INFINITY, Float32::INFINITY, -Float32::INFINITY, -Float32::INFINITY]
        list.items.each do |layer|
          4.times do |k|
            x = layer.outline.bounds[(k & 1) != 0 ? 2 : 0]
            y = layer.outline.bounds[(k & 2) != 0 ? 3 : 1]
            transform = layer.transform
            bx = transform.a * x + transform.c * y + transform.e
            by = transform.b * x + transform.d * y + transform.f
            bounds[0] = Math.min(bounds[0], bx)
            bounds[1] = Math.min(bounds[1], by)
            bounds[2] = Math.max(bounds[2], bx)
            bounds[3] = Math.max(bounds[3], by)
          end
        end
        bounds = StaticArray(Float32, 4).new(0.0_f32) if list.items.empty?
        glyph.bounds = bounds

        @layers.concat(list.items)
        @colors << glyph
        @color_use << @period
        slot = @colors.size.to_u32
        @color_table.set(key, slot)
      end
      @color_use[slot - 1] = @period
      glyph = @colors[slot - 1]
      {glyph, @layers[glyph.first, glyph.count]}
    end

    private def view(plane : PlaneData) : Plane
      Plane.new(plane.data, plane.rows, plane.texel_size, plane.used)
    end

    private def glyph_key(font : Font, glyph_id : UInt32) : UInt64
      (font.glyph_key.to_u64 << 32) | glyph_id.to_u64
    end

    private def color_key(font : Font, glyph_id : UInt32) : UInt64
      (font.color_state.key.to_u64 << 32) | glyph_id.to_u64
    end

    private def next_row(address : UInt64) : UInt64
      (address // W64 + 1) * W64
    end

    private def pack_location(address : UInt64) : UInt32
      (address % W64).to_u32 | (address // W64).to_u32 << 16
    end

    private def unpack_location(location : UInt32) : UInt64
      (location >> 16).to_u64 * W64 + (location & 0xFFFF_u32).to_u64
    end

    # Finds a glyph and marks it used in the current period.
    private def lookup(key : UInt64) : Glyph?
      slot = @glyph_table.get(key)
      return nil if slot == 0
      @glyph_use[slot - 1] = @period
      @glyphs[slot - 1]
    end

    private def insert(key : UInt64, glyph : Glyph) : Nil
      @glyph_table.set(key, @glyphs.size.to_u32 &+ 1)
      @glyph_use << @period
      @glyphs << glyph
    end

    # Lays out the texel chain so that both texels of every curve share a row.
    # With *write* false only the end address is computed.
    private def place_curves(outline : Outline, write : Bool) : UInt64
      cursor = @curves.used
      next_curve = 0

      texel_count = outline.texels.size
      curve_count = outline.curves.size
      k = 0
      while k < texel_count
        starts = next_curve < curve_count && outline.curve_texel[next_curve] == k
        continues = k > 0 && next_curve > 0 && outline.curve_texel[next_curve - 1] == k - 1

        if starts && cursor % W64 == W64 - 1
          if continues && write
            @curves.texel(cursor).as(UInt16*).copy_from(outline.texels[k].to_unsafe, 4)
          end
          cursor = next_row(cursor)
        end
        if write
          @curves.texel(cursor).as(UInt16*).copy_from(outline.texels[k].to_unsafe, 4)
        end
        if starts
          @curve_loc[next_curve] = pack_location(cursor) if write
          next_curve += 1
        end
        cursor += 1
        k += 1
      end
      cursor
    end

    # Lays out the band header and segments. The header and each segment stay
    # within one row because the shader indexes them without wrapping.
    private def place_bands(bands : Bands, write : Bool) : {Result, UInt64, UInt64}
      header = bands.count[0] &+ bands.count[1]
      cursor = @bands.used

      cursor = next_row(cursor) if cursor % W64 + header.to_u64 > W64
      base = cursor
      cursor += header.to_u64

      seg_count = bands.seg_count
      s = 0
      while s < seg_count
        len = bands.seg_len[s]
        return {Result::Limit, 0_u64, 0_u64} if len > TEXTURE_WIDTH
        cursor = next_row(cursor) if cursor % W64 + len.to_u64 > W64
        @seg_addr[s] = cursor
        return {Result::Limit, 0_u64, 0_u64} if cursor - base + len.to_u64 > 0xFFFF_u64
        if write
          i = 0_u64
          while i < len
            loc = @curve_loc[bands.indices[bands.seg_start[s].to_u64 + i]]
            t = @bands.texel(cursor + i).as(UInt16*)
            t[0] = (loc & 0xFFFF_u32).to_u16
            t[1] = (loc >> 16).to_u16
            i += 1
          end
        end
        cursor += len.to_u64
        s += 1
      end

      if write
        i = 0_u32
        while i < header
          ref = bands.refs[i]
          offset = ref.count != 0 ? @seg_addr[ref.segment] + ref.offset.to_u64 - base : 0_u64
          t = @bands.texel(base + i.to_u64).as(UInt16*)
          t[0] = ref.count.to_u16
          t[1] = offset.to_u16
          i += 1
        end
      end
      {Result::Ok, base, cursor}
    end

    # Phase 1 (calling fiber): FreeType load and outline copy. Non-outline
    # glyphs become empty.
    private def load_job(font : Font, job : Job) : Nil
      job.result = job.outline.capture(font, job.glyph_id)
      job.empty = job.result.unsupported?
      job.result = Result::Ok if job.empty
    end

    # Phase 2 (any fiber): curves and bands. Reads only the job and the atlas
    # settings, which are fixed at creation.
    private def band_job(job : Job) : Nil
      return unless job.result.ok? && !job.empty
      outline = job.outline
      job.result = outline.build(@cubic_tolerance)
      return unless job.result.ok?
      if outline.curves.empty?
        job.empty = true
        return
      end
      job.result = job.bands.build(outline.curves, outline.bounds, @max_bands, @band_slack)
    end

    # Phase 2 over a batch: worker fibers pull jobs from an atomic cursor, the
    # calling fiber included. Placement is serial, so results are identical
    # for any worker count.
    private def band_jobs(count : Int32, threads : UInt32) : Nil
      return if count == 0
      cursor = Atomic(Int32).new(0)
      work = -> {
        loop do
          i = cursor.add(1)
          break if i >= count
          band_job(@jobs[i])
        end
      }
      wanted = threads > 1 ? threads.to_i - 1 : 0
      wanted = count if wanted > count
      wanted = 63 if wanted > 63
      if wanted > 0
        done = Channel(Nil).new
        wanted.times { spawn { work.call; done.send(nil) } }
        work.call
        wanted.times { done.receive }
      else
        work.call
      end
    end

    # Phase 3: texel placement and the glyph record, in submission order.
    private def place_job(job : Job) : {Result, Glyph}
      outline = job.outline
      return {job.result, Glyph.new} unless job.result.ok?
      if job.empty
        return {Result::Ok, Glyph.new(advance: outline.advance, empty: true)}
      end

      bands = job.bands
      grow_locations(@curve_loc, outline.curves.size)
      grow_addresses(@seg_addr, bands.seg_count.to_i + 1)

      curve_start = @curves.used
      curve_end = place_curves(outline, false)
      result, glyph_address, band_end = place_bands(bands, false)
      return {result, Glyph.new} unless result.ok?
      result = @curves.reserve(curve_end)
      return {result, Glyph.new} unless result.ok?
      result = @bands.reserve(band_end)
      return {result, Glyph.new} unless result.ok?

      @curves.used = place_curves(outline, true)
      result, glyph_address, band_end = place_bands(bands, true)
      return {result, Glyph.new} unless result.ok?
      @bands.used = band_end
      @spans.add(pack_location(glyph_address),
        Span.new(curve_start, @curves.used, glyph_address, band_end, bands.count[0] &+ bands.count[1]))

      band_info = (bands.count[0] &- 1) | (bands.count[1] &- 1) << 16
      band_info |= FLAG_EVEN_ODD if outline.even_odd?
      band_info |= FLAG_REVERSED if outline.reversed?
      glyph = Glyph.new(
        advance: outline.advance,
        bounds: outline.bounds,
        band_scale: bands.scale,
        band_offset: bands.offset,
        location: pack_location(glyph_address),
        band_info: band_info,
        empty: false)
      {Result::Ok, glyph}
    end

    private def add_outlines(font : Font, glyph_ids : Indexable(UInt32), threads : UInt32) : Nil
      reserve_jobs(Math.min(glyph_ids.size, JOB_CHUNK))

      first = 0
      while first < glyph_ids.size
        n = 0
        while first < glyph_ids.size && n < JOB_CHUNK
          glyph_id = glyph_ids[first]
          first += 1
          key = glyph_key(font, glyph_id)
          next if lookup(key)
          queued = false
          j = 0
          while j < n && !queued
            queued = @jobs[j].key == key
            j += 1
          end
          next if queued
          raise Error.new(Result::Frozen) if @frozen

          job = @jobs[n]
          n += 1
          job.glyph_id = glyph_id
          job.key = key
          load_job(font, job)
          Slug.check(job.result)
        end

        band_jobs(n, threads)

        n.times do |j|
          job = @jobs[j]
          result, glyph = place_job(job)
          Slug.check(result)
          insert(job.key, glyph)
        end
      end
    end

    private def reserve_jobs(count : Int32) : Nil
      while @jobs.size < count
        @jobs << Job.new
      end
    end

    private def grow_locations(locations : Array(UInt32), need : Int) : Nil
      while locations.size < need
        locations << 0_u32
      end
    end

    private def grow_addresses(addresses : Array(UInt64), need : Int) : Nil
      while addresses.size < need
        addresses << 0_u64
      end
    end

    # Registers an outline location that the trimmed atlas keeps (each moved once).
    private def keep_location(t : Trim, location : UInt32) : Nil
      return if t.moved.get(location.to_u64) != 0
      t.old_locations << location
      t.moved.set(location.to_u64, t.old_locations.size.to_u32)
    end

    private def moved_location(t : Trim, location : UInt32) : UInt32
      t.locations[t.moved.get(location.to_u64) - 1]
    end

    # Copies [start, end) of src to the end of dst, one source row piece at a time.
    private def copy_range(dst : PlaneData, src : PlaneData, start : UInt64, stop : UInt64, pieces : Array(Piece)) : Result
      pieces.clear
      from = start
      while from < stop
        len = next_row(from) - from
        len = stop - from if from + len > stop
        to = dst.used
        to = next_row(to) if to % W64 + len > W64
        result = dst.reserve(to + len)
        return result unless result.ok?
        dst.texel(to).copy_from(src.texel(from), (len * src.texel_size.to_u64).to_i)
        dst.used = to + len
        pieces << Piece.new(from, to, len)
        from += len
      end
      Result::Ok
    end

    private def map_address(pieces : Array(Piece), address : UInt64) : UInt64
      pieces.each do |piece|
        return piece.to + (address - piece.from) if address >= piece.from && address < piece.from + piece.len
      end
      UInt64::MAX
    end

    # Moves one placed outline: copies its curves and bands, then rewrites
    # header offsets and curve locations.
    private def move_outline(t : Trim, location : UInt32) : {Result, UInt32}
      slot = @spans.table.get(location.to_u64)
      return {Result::Unsupported, 0_u32} if slot == 0 # not a placed outline: atlas state is inconsistent
      span = @spans.items[slot - 1]
      result = copy_range(t.curves, @curves, span.curve_start, span.curve_end, t.curve_pieces)
      return {result, 0_u32} unless result.ok?
      result = copy_range(t.bands, @bands, span.band_start, span.band_end, t.band_pieces)
      return {result, 0_u32} unless result.ok?

      base = map_address(t.band_pieces, span.band_start)
      t.band_pieces.each do |piece|
        address = piece.to
        stop = piece.to + piece.len
        while address < stop
          texel = t.bands.texel(address).as(UInt16*)
          if address < base + span.header.to_u64
            # Header: (curve count, offset of the list from the header).
            if texel[0] != 0
              list = map_address(t.band_pieces, span.band_start + texel[1].to_u64)
              return {Result::Limit, 0_u32} if list == UInt64::MAX || list - base > 0xFFFF_u64
              texel[1] = (list - base).to_u16
            end
          else
            # List entry: curve location (row gaps are left as is).
            curve = texel[1].to_u64 * W64 + texel[0].to_u64
            if curve >= span.curve_start && curve < span.curve_end
              moved = map_address(t.curve_pieces, curve)
              texel[0] = (moved % W64).to_u16
              texel[1] = (moved // W64).to_u16
            end
          end
          address += 1
        end
      end
      last_curve = t.curve_pieces[-1]
      last_band = t.band_pieces[-1]
      t.spans.add(pack_location(base),
        Span.new(t.curve_pieces[0].to, last_curve.to + last_curve.len, base, last_band.to + last_band.len,
          span.header))
      {Result::Ok, pack_location(base)}
    end
  end
end
