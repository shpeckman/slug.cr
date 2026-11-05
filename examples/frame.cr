# examples/frame.cr

class DemoFrame
  alias Gen = Proc(Int32, UInt32*, Nil)
  alias Delete = Proc(Int32, UInt32*, Nil)
  alias BindTexture = Proc(UInt32, UInt32, Nil)
  alias TexImage2D = Proc(UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, Void*, Nil)
  alias BindFramebuffer = Proc(UInt32, UInt32, Nil)
  alias FramebufferTexture2D = Proc(UInt32, UInt32, UInt32, UInt32, Int32, Nil)
  alias CheckFramebuffer = Proc(UInt32, UInt32)
  alias Viewport = Proc(Int32, Int32, Int32, Int32, Nil)
  alias ClearColor = Proc(Float32, Float32, Float32, Float32, Nil)
  alias Clear = Proc(UInt32, Nil)
  alias ReadPixels = Proc(Int32, Int32, Int32, Int32, UInt32, UInt32, Void*, Nil)
  alias Finish = Proc(Nil)

  @gen_textures : Gen
  @delete_textures : Delete
  @bind_texture : BindTexture
  @tex_image_2d : TexImage2D
  @gen_framebuffers : Gen
  @delete_framebuffers : Delete
  @bind_framebuffer : BindFramebuffer
  @framebuffer_texture_2d : FramebufferTexture2D
  @check_framebuffer : CheckFramebuffer
  @viewport : Viewport
  @clear_color : ClearColor
  @clear : Clear
  @read_pixels : ReadPixels
  @finish : Finish
  @texture = 0_u32
  @framebuffer = 0_u32

  def initialize(get_proc : Slug::GL::GetProc, @width : Int32, @height : Int32, offscreen : Bool)
    @gen_textures = load(Gen, get_proc, "glGenTextures")
    @delete_textures = load(Delete, get_proc, "glDeleteTextures")
    @bind_texture = load(BindTexture, get_proc, "glBindTexture")
    @tex_image_2d = load(TexImage2D, get_proc, "glTexImage2D")
    @gen_framebuffers = load(Gen, get_proc, "glGenFramebuffers")
    @delete_framebuffers = load(Delete, get_proc, "glDeleteFramebuffers")
    @bind_framebuffer = load(BindFramebuffer, get_proc, "glBindFramebuffer")
    @framebuffer_texture_2d = load(FramebufferTexture2D, get_proc, "glFramebufferTexture2D")
    @check_framebuffer = load(CheckFramebuffer, get_proc, "glCheckFramebufferStatus")
    @viewport = load(Viewport, get_proc, "glViewport")
    @clear_color = load(ClearColor, get_proc, "glClearColor")
    @clear = load(Clear, get_proc, "glClear")
    @read_pixels = load(ReadPixels, get_proc, "glReadPixels")
    @finish = load(Finish, get_proc, "glFinish")
    return unless offscreen

    @gen_textures.call(1, pointerof(@texture))
    @bind_texture.call(0x0DE1_u32, @texture)
    @tex_image_2d.call(0x0DE1_u32, 0_i32, 0x8058_i32, @width, @height, 0_i32, 0x1908_u32, 0x1401_u32, Pointer(Void).null)
    @gen_framebuffers.call(1, pointerof(@framebuffer))
    @bind_framebuffer.call(0x8D40_u32, @framebuffer)
    @framebuffer_texture_2d.call(0x8D40_u32, 0x8CE0_u32, 0x0DE1_u32, @texture, 0_i32)
    raise "OpenGL: incomplete demo framebuffer" if @check_framebuffer.call(0x8D40_u32) != 0x8CD5_u32
  end

  def clear : Nil
    @viewport.call(0_i32, 0_i32, @width, @height)
    @clear_color.call(0.035_f32, 0.045_f32, 0.065_f32, 1.0_f32)
    @clear.call(0x4000_u32)
  end

  def write_ppm(path : String) : Nil
    pixels = Bytes.new(@width.to_i64 * @height.to_i64 * 4)
    @finish.call
    @read_pixels.call(0_i32, 0_i32, @width, @height, 0x1908_u32, 0x1401_u32, pixels.to_unsafe.as(Void*))
    Dir.mkdir_p(File.dirname(path))
    File.open(path, "wb") do |file|
      file << "P6\n" << @width << ' ' << @height << "\n255\n"
      row = Bytes.new(@width * 3)
      (@height - 1).downto(0) do |y|
        @width.times do |x|
          source = (y * @width + x) * 4
          row[x * 3] = pixels[source]
          row[x * 3 + 1] = pixels[source + 1]
          row[x * 3 + 2] = pixels[source + 2]
        end
        file.write(row)
      end
    end
  end

  def close : Nil
    @delete_framebuffers.call(1, pointerof(@framebuffer)) if @framebuffer != 0
    @delete_textures.call(1, pointerof(@texture)) if @texture != 0
    @framebuffer = 0_u32
    @texture = 0_u32
  end

  private def load(type, get_proc, name)
    address = get_proc.call(name.to_unsafe)
    raise "OpenGL: missing #{name}" if address.null?
    type.new(address, Pointer(Void).null)
  end
end
