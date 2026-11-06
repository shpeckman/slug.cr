# src/slug/gl.cr

require "../slug"

module Slug
  # OpenGL 4.3 core and OpenGL ES 3.0+ rendering of Slug instances.
  module GL
    # Returns the address of an OpenGL entry point.
    alias GetProc = UInt8* -> Void*

    # Instances retained in a GPU buffer for repeated draws.
    class Batch
      # :nodoc:
      property buffer = 0_u32
      # :nodoc:
      property count = 0
      # :nodoc:
      property effects = false
    end

    # GPU renderer for one current OpenGL context and one synced atlas at a time.
    class Renderer
      private alias GetIntegerv = Proc(UInt32, Int32*, Nil)
      private alias GetString = Proc(UInt32, UInt8*)
      private alias GetStringi = Proc(UInt32, UInt32, UInt8*)
      private alias GenTextures = Proc(Int32, UInt32*, Nil)
      private alias DeleteTextures = Proc(Int32, UInt32*, Nil)
      private alias BindTexture = Proc(UInt32, UInt32, Nil)
      private alias ActiveTexture = Proc(UInt32, Nil)
      private alias TexImage2D = Proc(UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, Void*, Nil)
      private alias TexSubImage2D = Proc(UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, Void*, Nil)
      private alias TexParameteri = Proc(UInt32, UInt32, Int32, Nil)
      private alias PixelStorei = Proc(UInt32, Int32, Nil)
      private alias CreateShader = Proc(UInt32, UInt32)
      private alias ShaderSource = Proc(UInt32, Int32, UInt8**, Int32*, Nil)
      private alias CompileShader = Proc(UInt32, Nil)
      private alias GetShaderiv = Proc(UInt32, UInt32, Int32*, Nil)
      private alias GetShaderInfoLog = Proc(UInt32, Int32, Int32*, UInt8*, Nil)
      private alias DeleteShader = Proc(UInt32, Nil)
      private alias CreateProgram = Proc(UInt32)
      private alias AttachShader = Proc(UInt32, UInt32, Nil)
      private alias LinkProgram = Proc(UInt32, Nil)
      private alias GetProgramiv = Proc(UInt32, UInt32, Int32*, Nil)
      private alias GetProgramInfoLog = Proc(UInt32, Int32, Int32*, UInt8*, Nil)
      private alias DeleteProgram = Proc(UInt32, Nil)
      private alias UseProgram = Proc(UInt32, Nil)
      private alias GetUniformLocation = Proc(UInt32, UInt8*, Int32)
      private alias Uniform4fv = Proc(Int32, Int32, Float32*, Nil)
      private alias Uniform1i = Proc(Int32, Int32, Nil)
      private alias GenVertexArrays = Proc(Int32, UInt32*, Nil)
      private alias DeleteVertexArrays = Proc(Int32, UInt32*, Nil)
      private alias BindVertexArray = Proc(UInt32, Nil)
      private alias GenBuffers = Proc(Int32, UInt32*, Nil)
      private alias DeleteBuffers = Proc(Int32, UInt32*, Nil)
      private alias BindBuffer = Proc(UInt32, UInt32, Nil)
      private alias BufferData = Proc(UInt32, Int64, Void*, UInt32, Nil)
      private alias MapBufferRange = Proc(UInt32, Int64, Int64, UInt32, Void*)
      private alias VertexAttribPointer = Proc(UInt32, Int32, UInt32, UInt8, Int32, Void*, Nil)
      private alias VertexAttribDivisor = Proc(UInt32, UInt32, Nil)
      private alias EnableVertexAttribArray = Proc(UInt32, Nil)
      private alias DrawArraysInstanced = Proc(UInt32, Int32, Int32, Int32, Nil)
      private alias FenceSync = Proc(UInt32, UInt32, Void*)
      private alias ClientWaitSync = Proc(Void*, UInt32, UInt64, UInt32)
      private alias DeleteSync = Proc(Void*, Nil)
      private alias Enable = Proc(UInt32, Nil)
      private alias Disable = Proc(UInt32, Nil)
      private alias BlendFunc = Proc(UInt32, UInt32, Nil)
      private alias BlendEquation = Proc(UInt32, Nil)
      private alias CopyImageSubData = Proc(UInt32, UInt32, Int32, Int32, Int32, Int32, UInt32, UInt32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Nil)
      private alias BufferStorage = Proc(UInt32, Int64, Void*, UInt32, Nil)

      private TRIANGLE_STRIP             = 0x0005_u32
      private ONE                        =      1_u32
      private ONE_MINUS_SRC_ALPHA        = 0x0303_u32
      private CULL_FACE                  = 0x0B44_u32
      private BLEND                      = 0x0BE2_u32
      private UNPACK_ROW_LENGTH          = 0x0CF2_u32
      private UNPACK_SKIP_ROWS           = 0x0CF3_u32
      private UNPACK_SKIP_PIXELS         = 0x0CF4_u32
      private UNPACK_ALIGNMENT           = 0x0CF5_u32
      private MAX_TEXTURE_SIZE           = 0x0D33_u32
      private TEXTURE_2D                 = 0x0DE1_u32
      private UNSIGNED_SHORT             = 0x1403_u32
      private HALF_FLOAT                 = 0x140B_u32
      private RGBA                       = 0x1908_u32
      private VERSION                    = 0x1F02_u32
      private EXTENSIONS                 = 0x1F03_u32
      private NEAREST                    = 0x2600_i32
      private FUNC_ADD                   = 0x8006_u32
      private TEXTURE_MAG_FILTER         = 0x2800_u32
      private TEXTURE_MIN_FILTER         = 0x2801_u32
      private TEXTURE_WRAP_S             = 0x2802_u32
      private TEXTURE_WRAP_T             = 0x2803_u32
      private CLAMP_TO_EDGE              = 0x812F_i32
      private MAJOR_VERSION              = 0x821B_u32
      private MINOR_VERSION              = 0x821C_u32
      private NUM_EXTENSIONS             = 0x821D_u32
      private RG_INTEGER                 = 0x8228_u32
      private RG16UI                     = 0x823A_i32
      private TEXTURE0                   = 0x84C0_u32
      private RGBA16F                    = 0x881A_i32
      private ARRAY_BUFFER               = 0x8892_u32
      private STREAM_DRAW                = 0x88E0_u32
      private STATIC_DRAW                = 0x88E4_u32
      private PIXEL_UNPACK_BUFFER        = 0x88EC_u32
      private FRAGMENT_SHADER            = 0x8B30_u32
      private VERTEX_SHADER              = 0x8B31_u32
      private COMPILE_STATUS             = 0x8B81_u32
      private LINK_STATUS                = 0x8B82_u32
      private SYNC_GPU_COMMANDS_COMPLETE = 0x9117_u32
      private TIMEOUT_EXPIRED            = 0x911B_u32
      private WAIT_FAILED                = 0x911D_u32
      private MAP_WRITE_BIT              = 0x0002_u32
      private MAP_PERSISTENT_BIT         = 0x0040_u32
      private MAP_COHERENT_BIT           = 0x0080_u32
      private SYNC_FLUSH_COMMANDS_BIT    = 0x0001_u32

      private STREAM_INITIAL_SIZE    = 1 << 20
      private STREAM_ALIGN           =               256
      private STREAM_DRAWS_IN_FLIGHT =                 4
      private FENCE_TIMEOUT_NS       = 1_000_000_000_u64
      private INSTANCE_SIZE          = sizeof(Slug::Instance)

      private VERT_GL         = {{ read_file("#{__DIR__}/../../shaders/prelude_gl.glsl") + read_file("#{__DIR__}/../../shaders/slug.vert.glsl") }}
      private VERT_ES         = {{ read_file("#{__DIR__}/../../shaders/prelude_es.glsl") + read_file("#{__DIR__}/../../shaders/slug.vert.glsl") }}
      private FRAG_GL         = {{ read_file("#{__DIR__}/../../shaders/prelude_gl.glsl") + read_file("#{__DIR__}/../../shaders/slug.frag.glsl") }}
      private FRAG_ES         = {{ read_file("#{__DIR__}/../../shaders/prelude_es.glsl") + read_file("#{__DIR__}/../../shaders/slug.frag.glsl") }}
      private FRAG_GL_EFFECTS = {{ read_file("#{__DIR__}/../../shaders/prelude_gl.glsl") + read_file("#{__DIR__}/../../shaders/effects.glsl") + read_file("#{__DIR__}/../../shaders/slug.frag.glsl") }}
      private FRAG_ES_EFFECTS = {{ read_file("#{__DIR__}/../../shaders/prelude_es.glsl") + read_file("#{__DIR__}/../../shaders/effects.glsl") + read_file("#{__DIR__}/../../shaders/slug.frag.glsl") }}

      # :nodoc:
      struct Program
        property name = 0_u32
        property matrix = -1_i32
        property viewport = -1_i32
      end

      # :nodoc:
      class Texture
        property name = 0_u32
        property rows = 0_u32
        property synced = 0_u64
      end

      # :nodoc:
      struct Fence
        getter sync : Void*
        getter start : Int32
        getter finish : Int32

        def initialize(@sync : Void*, @start : Int32, @finish : Int32)
        end
      end

      # :nodoc:
      class Stream
        property buffer = 0_u32
        property map = Pointer(UInt8).null
        property size = 0
        property head = 0
        property fences = [] of Fence
        property fence_first = 0
      end

      # Returns the last backend diagnostic, or an empty string.
      getter error = ""

      private macro declare(ivar, type)
        @{{ivar}} : {{type}} = {{type}}.new(Pointer(Void).null, Pointer(Void).null)
      end

      declare get_integerv, GetIntegerv
      declare get_string, GetString
      declare get_stringi, GetStringi
      declare gen_textures, GenTextures
      declare delete_textures, DeleteTextures
      declare bind_texture, BindTexture
      declare active_texture, ActiveTexture
      declare tex_image_2d, TexImage2D
      declare tex_sub_image_2d, TexSubImage2D
      declare tex_parameteri, TexParameteri
      declare pixel_storei, PixelStorei
      declare create_shader, CreateShader
      declare shader_source, ShaderSource
      declare compile_shader, CompileShader
      declare get_shaderiv, GetShaderiv
      declare get_shader_info_log, GetShaderInfoLog
      declare delete_shader, DeleteShader
      declare create_program, CreateProgram
      declare attach_shader, AttachShader
      declare link_program, LinkProgram
      declare get_programiv, GetProgramiv
      declare get_program_info_log, GetProgramInfoLog
      declare delete_program, DeleteProgram
      declare use_program, UseProgram
      declare get_uniform_location, GetUniformLocation
      declare uniform_4fv, Uniform4fv
      declare uniform_1i, Uniform1i
      declare gen_vertex_arrays, GenVertexArrays
      declare delete_vertex_arrays, DeleteVertexArrays
      declare bind_vertex_array, BindVertexArray
      declare gen_buffers, GenBuffers
      declare delete_buffers, DeleteBuffers
      declare bind_buffer, BindBuffer
      declare buffer_data, BufferData
      declare map_buffer_range, MapBufferRange
      declare vertex_attrib_pointer, VertexAttribPointer
      declare vertex_attrib_divisor, VertexAttribDivisor
      declare enable_vertex_attrib_array, EnableVertexAttribArray
      declare draw_arrays_instanced, DrawArraysInstanced
      declare fence_sync, FenceSync
      declare client_wait_sync, ClientWaitSync
      declare delete_sync, DeleteSync
      declare enable, Enable
      declare disable, Disable
      declare blend_func, BlendFunc
      declare blend_equation, BlendEquation

      @copy_image : CopyImageSubData? = nil
      @buffer_storage : BufferStorage? = nil
      @programs = [Program.new, Program.new]
      @textures = [Texture.new, Texture.new]
      @stream = Stream.new
      @vao = 0_u32
      @atlas_id = 0_u64
      @es = false
      @max_texture_size = 0_i32
      @closed = false

      # Creates a renderer for the current context using *get_proc*.
      #
      # Raises `Error` with `Result::Unsupported` below GL 4.3 or GLES 3.0,
      # and with `Result::Backend` when shader compilation fails.
      def initialize(get_proc : GetProc)
        load @get_integerv, "glGetIntegerv", GetIntegerv
        load @get_string, "glGetString", GetString
        load @get_stringi, "glGetStringi", GetStringi
        load @gen_textures, "glGenTextures", GenTextures
        load @delete_textures, "glDeleteTextures", DeleteTextures
        load @bind_texture, "glBindTexture", BindTexture
        load @active_texture, "glActiveTexture", ActiveTexture
        load @tex_image_2d, "glTexImage2D", TexImage2D
        load @tex_sub_image_2d, "glTexSubImage2D", TexSubImage2D
        load @tex_parameteri, "glTexParameteri", TexParameteri
        load @pixel_storei, "glPixelStorei", PixelStorei
        load @create_shader, "glCreateShader", CreateShader
        load @shader_source, "glShaderSource", ShaderSource
        load @compile_shader, "glCompileShader", CompileShader
        load @get_shaderiv, "glGetShaderiv", GetShaderiv
        load @get_shader_info_log, "glGetShaderInfoLog", GetShaderInfoLog
        load @delete_shader, "glDeleteShader", DeleteShader
        load @create_program, "glCreateProgram", CreateProgram
        load @attach_shader, "glAttachShader", AttachShader
        load @link_program, "glLinkProgram", LinkProgram
        load @get_programiv, "glGetProgramiv", GetProgramiv
        load @get_program_info_log, "glGetProgramInfoLog", GetProgramInfoLog
        load @delete_program, "glDeleteProgram", DeleteProgram
        load @use_program, "glUseProgram", UseProgram
        load @get_uniform_location, "glGetUniformLocation", GetUniformLocation
        load @uniform_4fv, "glUniform4fv", Uniform4fv
        load @uniform_1i, "glUniform1i", Uniform1i
        load @gen_vertex_arrays, "glGenVertexArrays", GenVertexArrays
        load @delete_vertex_arrays, "glDeleteVertexArrays", DeleteVertexArrays
        load @bind_vertex_array, "glBindVertexArray", BindVertexArray
        load @gen_buffers, "glGenBuffers", GenBuffers
        load @delete_buffers, "glDeleteBuffers", DeleteBuffers
        load @bind_buffer, "glBindBuffer", BindBuffer
        load @buffer_data, "glBufferData", BufferData
        load @map_buffer_range, "glMapBufferRange", MapBufferRange
        load @vertex_attrib_pointer, "glVertexAttribPointer", VertexAttribPointer
        load @vertex_attrib_divisor, "glVertexAttribDivisor", VertexAttribDivisor
        load @enable_vertex_attrib_array, "glEnableVertexAttribArray", EnableVertexAttribArray
        load @draw_arrays_instanced, "glDrawArraysInstanced", DrawArraysInstanced
        load @fence_sync, "glFenceSync", FenceSync
        load @client_wait_sync, "glClientWaitSync", ClientWaitSync
        load @delete_sync, "glDeleteSync", DeleteSync
        load @enable, "glEnable", Enable
        load @disable, "glDisable", Disable
        load @blend_func, "glBlendFunc", BlendFunc
        load @blend_equation, "glBlendEquation", BlendEquation

        version = @get_string.call(VERSION)
        @es = !version.null? && String.new(version).includes?("OpenGL ES")
        major = 0_i32
        minor = 0_i32
        @get_integerv.call(MAJOR_VERSION, pointerof(major))
        @get_integerv.call(MINOR_VERSION, pointerof(minor))
        @get_integerv.call(MAX_TEXTURE_SIZE, pointerof(@max_texture_size))
        supported = @es ? major >= 3 : major > 4 || major == 4 && minor >= 3
        unless supported && @max_texture_size >= TEXTURE_WIDTH
          raise Error.new(Result::Unsupported, "Slug needs OpenGL 4.3 or OpenGL ES 3.0 and #{TEXTURE_WIDTH}-texel textures")
        end
        load_optional(get_proc, major, minor)
        begin
          build_program(0)
          build_vertex_array
        rescue ex
          close
          raise ex
        end
      end

      # Creates a renderer with a loader block receiving C entry-point names.
      def self.new(&get_proc : GetProc) : Renderer
        new(get_proc)
      end

      # Returns whether the current context is OpenGL ES.
      def es? : Bool
        @es
      end

      # Returns whether streamed draws use persistent coherent buffer mapping.
      def persistent_streaming? : Bool
        !@buffer_storage.nil?
      end

      # Uploads atlas texels written since the previous sync.
      #
      # Texture growth copies existing contents on the GPU when supported,
      # otherwise re-uploads them. A changed atlas ID replaces both textures.
      def sync(atlas : Atlas) : Nil
        ensure_open
        @error = ""
        if @atlas_id != atlas.id
          @textures.each_with_index do |texture, i|
            delete_texture(texture)
            @textures[i] = Texture.new
          end
          @atlas_id = atlas.id
        end

        @bind_buffer.call(PIXEL_UNPACK_BUFFER, 0_u32)
        @pixel_storei.call(UNPACK_ALIGNMENT, 4_i32)
        @pixel_storei.call(UNPACK_ROW_LENGTH, 0_i32)
        @pixel_storei.call(UNPACK_SKIP_ROWS, 0_i32)
        @pixel_storei.call(UNPACK_SKIP_PIXELS, 0_i32)
        sync_plane(@textures[0], RGBA16F, RGBA, HALF_FLOAT, atlas.curves)
        sync_plane(@textures[1], RG16UI, RG_INTEGER, UNSIGNED_SHORT, atlas.bands)
      end

      # Draws instances using column-major object-to-clip matrix *mvp*.
      #
      # Viewport dimensions are in pixels and drive dynamic dilation. Instances
      # with dilation select the effects shader automatically.
      def draw(instances : Indexable(Instance), mvp : StaticArray(Float32, 16), viewport_width : Float32,
               viewport_height : Float32) : Nil
        ensure_open
        return if instances.empty?
        check_draw(instances.size)
        effects = any_effects(instances)
        bytes = instances.size * INSTANCE_SIZE
        if storage = @buffer_storage
          offset = stream_write(instances.to_unsafe.as(UInt8*), bytes)
          begin
            draw_range(effects, @stream.buffer, offset, 0, instances.size, mvp, viewport_width, viewport_height)
          ensure
            stream_fence(offset, offset + bytes)
          end
        else
          ensure_stream_buffer
          @bind_buffer.call(ARRAY_BUFFER, @stream.buffer)
          @buffer_data.call(ARRAY_BUFFER, bytes.to_i64, instances.to_unsafe.as(Void*), STREAM_DRAW)
          draw_range(effects, @stream.buffer, 0, 0, instances.size, mvp, viewport_width, viewport_height)
        end
      end

      # Creates a retained batch, uploading *instances* once.
      def create_batch(instances : Indexable(Instance)) : Batch
        ensure_open
        check_count(instances.size)
        batch = Batch.new
        name = 0_u32
        @gen_buffers.call(1, pointerof(name))
        batch.buffer = name
        begin
          update_batch(batch, instances)
        rescue ex
          destroy_batch(batch)
          raise ex
        end
        batch
      end

      # Replaces a retained batch's instances.
      def update_batch(batch : Batch, instances : Indexable(Instance)) : Nil
        ensure_open
        check_count(instances.size)
        @bind_buffer.call(ARRAY_BUFFER, batch.buffer)
        bytes = instances.size * INSTANCE_SIZE
        data = instances.empty? ? Pointer(Void).null : instances.to_unsafe.as(Void*)
        @buffer_data.call(ARRAY_BUFFER, bytes.to_i64, data, STATIC_DRAW)
        batch.count = instances.size
        batch.effects = any_effects(instances)
      end

      # Destroys a retained batch's GPU buffer. The batch must not be drawn again.
      def destroy_batch(batch : Batch) : Nil
        return if batch.buffer == 0
        name = batch.buffer
        @delete_buffers.call(1, pointerof(name))
        batch.buffer = 0_u32
        batch.count = 0
      end

      # Draws every instance in *batch*.
      def draw_batch(batch : Batch, mvp : StaticArray(Float32, 16), viewport_width : Float32,
                     viewport_height : Float32) : Nil
        draw_batch_range(batch, 0, batch.count, mvp, viewport_width, viewport_height)
      end

      # Draws *count* instances in *batch* starting at *first*.
      def draw_batch_range(batch : Batch, first : Int32, count : Int32, mvp : StaticArray(Float32, 16),
                           viewport_width : Float32, viewport_height : Float32) : Nil
        ensure_open
        unless first >= 0 && count >= 0 && first <= batch.count && count <= batch.count - first
          raise Error.new(Result::InvalidArgument, "batch range is outside the batch")
        end
        return if count == 0
        check_draw(count)
        draw_range(batch.effects, batch.buffer, 0, first, count, mvp, viewport_width, viewport_height)
      end

      # Releases renderer-owned GL objects. Batches are released separately.
      def close : Nil
        return if @closed
        release_stream
        @textures.each { |texture| delete_texture(texture) }
        if @vao != 0
          @delete_vertex_arrays.call(1, pointerof(@vao))
          @vao = 0_u32
        end
        @programs.each do |program|
          next if program.name == 0
          @delete_program.call(program.name)
          program.name = 0_u32
        end
        @closed = true
      end

      private macro load(ivar, name, type)
        %address = get_proc.call({{name}}.to_unsafe)
        if %address.null?
          raise Error.new(Result::Unsupported, "missing OpenGL entry point: " + {{name}})
        end
        {{ivar}} = {{type}}.new(%address, Pointer(Void).null)
      end

      private def ensure_open : Nil
        raise Error.new(Result::InvalidArgument, "renderer is closed") if @closed
      end

      private def check_count(count : Int32) : Nil
        raise Error.new(Result::Limit, "too many instances for OpenGL") if count > Int32::MAX
      end

      private def check_draw(count : Int32) : Nil
        check_count(count)
        if @textures[0].name == 0
          @error = "draw before sync"
          raise Error.new(Result::Backend, @error)
        end
        @error = ""
      end

      private def has_extension(name : String) : Bool
        count = 0_i32
        @get_integerv.call(NUM_EXTENSIONS, pointerof(count))
        count.times do |i|
          extension = @get_stringi.call(EXTENSIONS, i.to_u32)
          return true if !extension.null? && String.new(extension) == name
        end
        false
      end

      private def optional(type, get_proc : GetProc, name : String)
        address = get_proc.call(name.to_unsafe)
        address.null? ? nil : type.new(address, Pointer(Void).null)
      end

      private def load_optional(get_proc : GetProc, major : Int32, minor : Int32) : Nil
        copy = if !@es || major > 3 || major == 3 && minor >= 2
                 "glCopyImageSubData"
               elsif has_extension("GL_EXT_copy_image")
                 "glCopyImageSubDataEXT"
               elsif has_extension("GL_OES_copy_image")
                 "glCopyImageSubDataOES"
               else
                 nil
               end
        @copy_image = optional(CopyImageSubData, get_proc, copy) if copy

        storage = if !@es && (major > 4 || major == 4 && minor >= 4 || has_extension("GL_ARB_buffer_storage"))
                    "glBufferStorage"
                  elsif @es && has_extension("GL_EXT_buffer_storage")
                    "glBufferStorageEXT"
                  else
                    nil
                  end
        @buffer_storage = optional(BufferStorage, get_proc, storage) if storage
      end

      private def compile(stage : UInt32, source : String) : UInt32
        shader = @create_shader.call(stage)
        pointer = source.to_unsafe
        @shader_source.call(shader, 1_i32, pointerof(pointer), Pointer(Int32).null)
        @compile_shader.call(shader)
        ok = 0_i32
        @get_shaderiv.call(shader, COMPILE_STATUS, pointerof(ok))
        if ok == 0
          log = Bytes.new(4096)
          @get_shader_info_log.call(shader, log.size, Pointer(Int32).null, log.to_unsafe)
          @error = "#{stage == VERTEX_SHADER ? "vertex" : "fragment"} shader: #{String.new(log.to_unsafe)}"
          @delete_shader.call(shader)
          raise Error.new(Result::Backend, @error)
        end
        shader
      end

      private def build_program(variant : Int32) : Nil
        vertex = compile(VERTEX_SHADER, @es ? VERT_ES : VERT_GL)
        fragment_source = case {variant, @es}
                          when {0, false} then FRAG_GL
                          when {0, true}  then FRAG_ES
                          when {1, false} then FRAG_GL_EFFECTS
                          else                 FRAG_ES_EFFECTS
                          end
        begin
          fragment = compile(FRAGMENT_SHADER, fragment_source)
        rescue ex
          @delete_shader.call(vertex)
          raise ex
        end

        program = Program.new
        program.name = @create_program.call
        @attach_shader.call(program.name, vertex)
        @attach_shader.call(program.name, fragment)
        @link_program.call(program.name)
        @delete_shader.call(vertex)
        @delete_shader.call(fragment)
        ok = 0_i32
        @get_programiv.call(program.name, LINK_STATUS, pointerof(ok))
        if ok == 0
          log = Bytes.new(4096)
          @get_program_info_log.call(program.name, log.size, Pointer(Int32).null, log.to_unsafe)
          @error = "link: #{String.new(log.to_unsafe)}"
          @delete_program.call(program.name)
          raise Error.new(Result::Backend, @error)
        end
        program.matrix = @get_uniform_location.call(program.name, "slug_matrix".to_unsafe)
        program.viewport = @get_uniform_location.call(program.name, "slug_viewport".to_unsafe)
        @use_program.call(program.name)
        @uniform_1i.call(@get_uniform_location.call(program.name, "slug_curve".to_unsafe), 0_i32)
        @uniform_1i.call(@get_uniform_location.call(program.name, "slug_band".to_unsafe), 1_i32)
        @use_program.call(0_u32)
        @programs[variant] = program
      end

      private def build_vertex_array : Nil
        @gen_vertex_arrays.call(1, pointerof(@vao))
        @bind_vertex_array.call(@vao)
        6.times do |i|
          @enable_vertex_attrib_array.call(i.to_u32)
          @vertex_attrib_divisor.call(i.to_u32, 1_u32)
        end
        @bind_vertex_array.call(0_u32)
      end

      private def create_texture(internal : Int32, format : UInt32, type : UInt32, rows : UInt32) : UInt32
        name = 0_u32
        @gen_textures.call(1, pointerof(name))
        @bind_texture.call(TEXTURE_2D, name)
        @tex_parameteri.call(TEXTURE_2D, TEXTURE_MIN_FILTER, NEAREST)
        @tex_parameteri.call(TEXTURE_2D, TEXTURE_MAG_FILTER, NEAREST)
        @tex_parameteri.call(TEXTURE_2D, TEXTURE_WRAP_S, CLAMP_TO_EDGE)
        @tex_parameteri.call(TEXTURE_2D, TEXTURE_WRAP_T, CLAMP_TO_EDGE)
        @tex_image_2d.call(TEXTURE_2D, 0_i32, internal, TEXTURE_WIDTH.to_i32, rows.to_i32, 0_i32, format, type, Pointer(Void).null)
        name
      end

      private def delete_texture(texture : Texture) : Nil
        return if texture.name == 0
        name = texture.name
        @delete_textures.call(1, pointerof(name))
        texture.name = 0_u32
      end

      private def sync_plane(texture : Texture, internal : Int32, format : UInt32, type : UInt32, plane : Plane) : Nil
        if plane.rows > @max_texture_size
          @error = "atlas needs #{plane.rows} rows; GL_MAX_TEXTURE_SIZE is #{@max_texture_size}"
          raise Error.new(Result::Backend, @error)
        end
        if texture.name == 0 || texture.rows != plane.rows
          name = create_texture(internal, format, type, plane.rows)
          synced_rows = (texture.synced + plane.width - 1) // plane.width
          copy_rows = Math.min(synced_rows, plane.rows.to_u64).to_u32
          if texture.name != 0 && (copy = @copy_image) && copy_rows > 0
            copy.call(texture.name, TEXTURE_2D, 0_i32, 0_i32, 0_i32, 0_i32, name, TEXTURE_2D, 0_i32, 0_i32, 0_i32, 0_i32,
              TEXTURE_WIDTH.to_i32, copy_rows.to_i32, 1_i32)
          else
            texture.synced = 0_u64
          end
          delete_texture(texture)
          texture.name = name
          texture.rows = plane.rows
        end

        first = (texture.synced // plane.width).to_u32
        last = ((plane.used + plane.width - 1) // plane.width).to_u32
        if last > first
          row_bytes = plane.width.to_i64 * plane.texel_size
          @bind_texture.call(TEXTURE_2D, texture.name)
          data = (plane.data.to_unsafe + first.to_i64 * row_bytes).as(Void*)
          @tex_sub_image_2d.call(TEXTURE_2D, 0_i32, 0_i32, first.to_i32, TEXTURE_WIDTH.to_i32, (last - first).to_i32,
            format, type, data)
        end
        texture.synced = plane.used
      end

      private def any_effects(instances : Indexable(Instance)) : Bool
        instances.any? { |instance| instance.dilation != 0.0_f32 }
      end

      private def draw_range(effects : Bool, buffer : UInt32, offset : Int32, first : Int32, count : Int32,
                             mvp : StaticArray(Float32, 16), viewport_width : Float32, viewport_height : Float32) : Nil
        variant = effects ? 1 : 0
        build_program(variant) if @programs[variant].name == 0
        program = @programs[variant]
        rows = StaticArray(Float32, 16).new(0.0_f32)
        4.times do |row|
          4.times { |column| rows[row * 4 + column] = mvp[column * 4 + row] }
        end
        viewport = StaticArray[viewport_width, viewport_height, 0.0_f32, 0.0_f32]

        @active_texture.call(TEXTURE0)
        @bind_texture.call(TEXTURE_2D, @textures[0].name)
        @active_texture.call(TEXTURE0 + 1)
        @bind_texture.call(TEXTURE_2D, @textures[1].name)
        @active_texture.call(TEXTURE0)
        @bind_vertex_array.call(@vao)
        @bind_buffer.call(ARRAY_BUFFER, buffer)
        @enable.call(BLEND)
        @disable.call(CULL_FACE)
        @blend_equation.call(FUNC_ADD)
        @blend_func.call(ONE, ONE_MINUS_SRC_ALPHA)
        @use_program.call(program.name)
        @uniform_4fv.call(program.matrix, 4_i32, rows.to_unsafe)
        @uniform_4fv.call(program.viewport, 1_i32, viewport.to_unsafe)
        start = offset + first * INSTANCE_SIZE
        6.times do |i|
          size = i == 5 ? 1_i32 : 4_i32
          @vertex_attrib_pointer.call(i.to_u32, size, 0x1406_u32, 0_u8, INSTANCE_SIZE.to_i32,
            Pointer(Void).new((start + i * 16).to_u64))
        end
        @draw_arrays_instanced.call(TRIANGLE_STRIP, 0_i32, 4_i32, count.to_i32)
        @bind_vertex_array.call(0_u32)
      end

      private def ensure_stream_buffer : Nil
        return unless @stream.buffer == 0
        name = 0_u32
        @gen_buffers.call(1, pointerof(name))
        @stream.buffer = name
      end

      private def release_stream : Nil
        @stream.fence_first.upto(@stream.fences.size - 1) do |i|
          @delete_sync.call(@stream.fences[i].sync)
        end
        @stream.fences.clear
        @stream.fence_first = 0
        if @stream.buffer != 0
          name = @stream.buffer
          @delete_buffers.call(1, pointerof(name))
        end
        @stream.buffer = 0_u32
        @stream.map = Pointer(UInt8).null
        @stream.size = 0
        @stream.head = 0
      end

      private def wait_fence : Nil
        fence = @stream.fences[@stream.fence_first]
        status = 0_u32
        loop do
          status = @client_wait_sync.call(fence.sync, SYNC_FLUSH_COMMANDS_BIT, FENCE_TIMEOUT_NS)
          break unless status == TIMEOUT_EXPIRED
        end
        @delete_sync.call(fence.sync)
        @stream.fence_first += 1
        if @stream.fence_first == @stream.fences.size
          @stream.fences.clear
          @stream.fence_first = 0
        end
        if status == WAIT_FAILED
          @error = "glClientWaitSync failed"
          raise Error.new(Result::Backend, @error)
        end
      end

      private def create_stream(size : Int32) : Nil
        release_stream
        name = 0_u32
        @gen_buffers.call(1, pointerof(name))
        @stream.buffer = name
        @bind_buffer.call(ARRAY_BUFFER, @stream.buffer)
        flags = MAP_WRITE_BIT | MAP_PERSISTENT_BIT | MAP_COHERENT_BIT
        @buffer_storage.not_nil!.call(ARRAY_BUFFER, size.to_i64, Pointer(Void).null, flags)
        @stream.map = @map_buffer_range.call(ARRAY_BUFFER, 0_i64, size.to_i64, flags).as(UInt8*)
        if @stream.map.null?
          release_stream
          @error = "persistent mapping of #{size} bytes failed"
          raise Error.new(Result::Backend, @error)
        end
        @stream.size = size
      end

      private def stream_write(data : UInt8*, bytes : Int32) : Int
        if bytes * STREAM_DRAWS_IN_FLIGHT > @stream.size
          size = @stream.size == 0 ? STREAM_INITIAL_SIZE : @stream.size
          while size < bytes * STREAM_DRAWS_IN_FLIGHT
            size *= 2
          end
          create_stream(size)
        end
        if @stream.head + bytes > @stream.size
          while @stream.fence_first < @stream.fences.size && @stream.fences[@stream.fence_first].start >= @stream.head
            wait_fence
          end
          @stream.head = 0
        end
        while @stream.fence_first < @stream.fences.size &&
              @stream.fences[@stream.fence_first].start < @stream.head + bytes &&
              @stream.fences[@stream.fence_first].finish > @stream.head
          wait_fence
        end
        (@stream.map + @stream.head).copy_from(data, bytes)
        offset = @stream.head
        @stream.head = (@stream.head + bytes + STREAM_ALIGN - 1) & ~(STREAM_ALIGN - 1)
        offset
      end

      private def stream_fence(start : Int32, finish : Int32) : Nil
        if @stream.fence_first >= 64
          @stream.fences = @stream.fences[@stream.fence_first..]
          @stream.fence_first = 0
        end
        sync = @fence_sync.call(SYNC_GPU_COMMANDS_COMPLETE, 0_u32)
        @stream.fences << Fence.new(sync, start, finish)
      end
    end
  end
end
