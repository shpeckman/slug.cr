# src/slug/bands.cr
module Slug
  # :nodoc:
  #
  # A band's curve list: a run inside a stored segment.
  struct BandRef
    getter segment : UInt32
    getter offset : UInt32
    getter count : UInt32

    def initialize(@segment : UInt32 = 0_u32, @offset : UInt32 = 0_u32, @count : UInt32 = 0_u32)
    end
  end

  # :nodoc:
  #
  # Band partition of one outline, ported from band.c: per-axis curve lists
  # sorted for the shader's early exit, with equal lists sharing one stored
  # segment. Axis 0 is x (vertical bands), axis 1 is y (horizontal bands);
  # `refs` holds the horizontal bands first, then the vertical bands, matching
  # the band texture header order.
  #
  # One instance per atlas job: `build` reuses every buffer, `reset` clears
  # the partition but keeps them, `free` releases them.
  class Bands
    private struct KeyedCurve
      property key : Float32
      property index : UInt32
      # Range on the band axis, widened by the band epsilon.
      property lo : Float32
      property hi : Float32

      def initialize(@key : Float32 = 0.0_f32, @index : UInt32 = 0_u32, @lo : Float32 = 0.0_f32, @hi : Float32 = 0.0_f32)
      end
    end

    # Bands per axis (x, y).
    getter count : StaticArray(UInt32, 2) = StaticArray[0_u32, 0_u32]

    # Band index scale per axis.
    getter scale : StaticArray(Float32, 2) = StaticArray[0.0_f32, 0.0_f32]

    # Band index offset per axis.
    getter offset : StaticArray(Float32, 2) = StaticArray[0.0_f32, 0.0_f32]

    # Stored list segments.
    getter seg_count = 0_u32

    # Curve indices stored over all segments.
    getter index_count = 0_u32

    @refs = [] of BandRef
    @seg_start = [] of UInt32
    @seg_len = [] of UInt32
    @indices = [] of UInt32
    # scratch
    @lists = [] of UInt32
    @lists_used = 0_u32
    @list_start = [] of UInt32
    @list_len = [] of UInt32
    @order = [] of UInt32
    @keyed = [] of KeyedCurve
    @mean = Array(Float32).new(MAX_BANDS.to_i + 1, 0.0_f32)

    # The band list refs in header order: horizontal bands first, then vertical.
    def refs : Slice(BandRef)
      slice_of(@refs)[0, (@count[0] &+ @count[1]).to_i]
    end

    # First curve index of every stored segment (`seg_count` entries).
    def seg_start : Slice(UInt32)
      slice_of(@seg_start)[0, @seg_count.to_i]
    end

    # Length of every stored segment (`seg_count` entries).
    def seg_len : Slice(UInt32)
      slice_of(@seg_len)[0, @seg_count.to_i]
    end

    # Curve indices of the stored segments, concatenated (`index_count` entries).
    def indices : Slice(UInt32)
      slice_of(@indices)[0, @index_count.to_i]
    end

    # Clears the partition but keeps every buffer for the next `build`.
    def reset : Nil
      @seg_count = 0_u32
      @index_count = 0_u32
      @lists_used = 0_u32
    end

    # Releases every buffer.
    def free : Nil
      @count = StaticArray[0_u32, 0_u32]
      @scale = StaticArray[0.0_f32, 0.0_f32]
      @offset = StaticArray[0.0_f32, 0.0_f32]
      @refs = [] of BandRef
      @seg_start = [] of UInt32
      @seg_len = [] of UInt32
      @indices = [] of UInt32
      @lists = [] of UInt32
      @list_start = [] of UInt32
      @list_len = [] of UInt32
      @order = [] of UInt32
      @keyed = [] of KeyedCurve
      reset
    end

    # Partitions *curves* (half-quantized em space) inside *bounds* (x min,
    # y min, x max, y max) into at most *max_bands* per axis, preferring the
    # count with the fewest curves per band and the smallest count within
    # *slack* of that minimum. Returns `Result::Ok`.
    def build(curves : Indexable(Curve), bounds : Indexable(Float32), max_bands : UInt32, slack : Float32) : Result
      reset

      # Header order: horizontal bands (y axis) first, then vertical bands (x axis).
      band_cursor = build_axis(curves, 1, bounds[1], bounds[3] - bounds[1], max_bands, slack, 0_u32)
      build_axis(curves, 0, bounds[0], bounds[2] - bounds[0], max_bands, slack, band_cursor)

      total = @count[0] &+ @count[1]
      grow(@refs, total.to_i, BandRef.new)
      share_lists(total)
      Result::Ok
    end

    # Appends the lists of one axis' bands at *first_band* and returns the
    # band count. Curves are sorted once; filling the buckets in that order
    # leaves every list sorted.
    private def build_axis(curves : Indexable(Curve), axis : Int, lo : Float32, extent : Float32,
                           max_bands : UInt32, slack : Float32, first_band : UInt32) : UInt32
      grow(@keyed, curves.size, KeyedCurve.new)
      keyed = slice_of(@keyed)
      eligible = 0
      curves.each_with_index do |curve, i|
        next if excluded(curve, axis)
        keyed[eligible] = KeyedCurve.new(
          key: curve_max(curve, 1 - axis),
          index: i.to_u32,
          lo: curve_min(curve, axis) - BAND_EPSILON,
          hi: curve_max(curve, axis) + BAND_EPSILON)
        eligible += 1
      end

      # Descending key, ascending index: the order the shader's early exit relies on.
      keyed[0, eligible].sort! do |x, y|
        x.key != y.key ? (x.key < y.key ? 1 : -1) : (x.index <=> y.index)
      end

      n = choose_count(keyed[0, eligible], lo, extent, max_bands, slack)
      @count[axis] = n
      @scale[axis] = extent > 0.0_f32 ? n.to_f32 / extent : 0.0_f32
      @offset[axis] = extent > 0.0_f32 ? -lo * @scale[axis] : 0.0_f32

      grow(@list_start, (first_band + n).to_i, 0_u32)
      grow(@list_len, (first_band + n).to_i, 0_u32)

      inv_size = @scale[axis]
      list_start = slice_of(@list_start)
      len = slice_of(@list_len)[first_band.to_i, n.to_i]
      n.times { |b| len[b] = 0_u32 }
      eligible.times do |k|
        blo = band_index(keyed[k].lo, lo, inv_size, n)
        bhi = band_index(keyed[k].hi, lo, inv_size, n)
        blo.upto(bhi) { |b| len[b] += 1_u32 }
      end

      used = @lists_used
      n.times do |b|
        list_start[first_band + b] = used
        used += len[b]
      end
      grow(@lists, used.to_i, 0_u32)
      @lists_used = used

      n.times { |b| len[b] = 0_u32 }
      lists = slice_of(@lists)
      eligible.times do |k|
        blo = band_index(keyed[k].lo, lo, inv_size, n)
        bhi = band_index(keyed[k].hi, lo, inv_size, n)
        blo.upto(bhi) do |b|
          lists[list_start[first_band + b] + len[b]] = keyed[k].index
          len[b] += 1_u32
        end
      end
      n
    end

    # Band count with the fewest curves per band on average (the per-pixel loop
    # length), preferring fewer bands within *slack* (a fraction) of that minimum.
    private def choose_count(keyed : Slice(KeyedCurve), lo : Float32, extent : Float32,
                             max_bands : UInt32, slack : Float32) : UInt32
      return 1_u32 if !(extent > 0.0_f32) || keyed.empty?

      mean = slice_of(@mean)
      best = Float32::INFINITY
      1_u32.upto(max_bands) do |n|
        inv_size = n.to_f32 / extent
        entries = 0_u64
        keyed.each do |curve|
          entries += (band_index(curve.hi, lo, inv_size, n) - band_index(curve.lo, lo, inv_size, n) + 1_u32).to_u64
        end
        mean[n] = entries.to_f32 / n.to_f32
        best = Math.min(best, mean[n])
      end
      1_u32.upto(max_bands) do |n|
        return n if mean[n] <= best * (1.0_f32 + slack)
      end
      max_bands
    end

    # Stores each list once; lists equal to a contiguous run of a stored segment reuse it.
    private def share_lists(band_total : UInt32) : Nil
      grow(@order, band_total.to_i, 0_u32)
      order = slice_of(@order)
      list_len = slice_of(@list_len)
      band_total.times do |i|
        v = i
        j = i
        while j > 0 && list_len[order[j - 1]] < list_len[v]
          order[j] = order[j - 1]
          j -= 1
        end
        order[j] = v
      end

      lists = slice_of(@lists)
      list_start = slice_of(@list_start)
      band_total.times do |k|
        b = order[k]
        count = list_len[b]
        if count == 0
          @refs[b] = BandRef.new
          next
        end
        list = lists[list_start[b], count]
        if ref = find_run(list)
          @refs[b] = ref
          next
        end
        s = @seg_count
        grow(@seg_start, s.to_i + 1, 0_u32)
        grow(@seg_len, s.to_i + 1, 0_u32)
        grow(@indices, (@index_count + count).to_i, 0_u32)
        @seg_start[s] = @index_count
        @seg_len[s] = count
        slice_of(@indices)[@index_count, count].copy_from(list)
        @index_count += count
        @seg_count += 1
        @refs[b] = BandRef.new(s, 0_u32, count)
      end
    end

    private def find_run(list : Slice(UInt32)) : BandRef?
      count = list.size.to_u32
      indices = slice_of(@indices)
      @seg_count.times do |s|
        len = @seg_len[s]
        seg = indices[@seg_start[s], len]
        off = 0_u32
        while off + count <= len
          if seg[off] == list[0] && seg[off, count] == list
            return BandRef.new(s, off, count)
          end
          off += 1_u32
        end
      end
      nil
    end

    # Axis 0 = x (vertical bands), axis 1 = y (horizontal bands).
    private def coord(p : Vec2, axis : Int) : Float32
      axis != 0 ? p.y : p.x
    end

    private def curve_min(c : Curve, axis : Int) : Float32
      Math.min(coord(c.p[0], axis), Math.min(coord(c.p[1], axis), coord(c.p[2], axis)))
    end

    private def curve_max(c : Curve, axis : Int) : Float32
      Math.max(coord(c.p[0], axis), Math.max(coord(c.p[1], axis), coord(c.p[2], axis)))
    end

    # A straight line parallel to the rays of this axis' bands cannot change the winding number.
    private def excluded(c : Curve, axis : Int) : Bool
      a = coord(c.p[0], axis)
      a == coord(c.p[1], axis) && a == coord(c.p[2], axis)
    end

    private def band_index(v : Float32, lo : Float32, inv_size : Float32, n : UInt32) : UInt32
      t = (v - lo) * inv_size
      b = t > 0.0_f32 ? t.to_u32 : 0_u32 # truncation == floor for t >= 0
      b < n ? b : n - 1_u32
    end

    # Slice over an array's whole buffer; re-take it after every `grow`.
    private def slice_of(list : Array(T)) : Slice(T) forall T
      list.to_unsafe.to_slice(list.size)
    end

    private def grow(list : Array(T), size : Int, fill : T) : Nil forall T
      while list.size < size
        list.push(fill)
      end
    end
  end
end
