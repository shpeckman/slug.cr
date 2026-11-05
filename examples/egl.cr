# examples/egl.cr

@[Link("EGL")]
lib LibEGL
  fun eglGetPlatformDisplay(platform : UInt32, native : Void*, attribs : Int32*) : Void*
  fun eglInitialize(display : Void*, major : Int32*, minor : Int32*) : Int32
  fun eglBindAPI(api : UInt32) : Int32
  fun eglChooseConfig(display : Void*, attribs : Int32*, configs : Void**, count : Int32, found : Int32*) : Int32
  fun eglCreateContext(display : Void*, config : Void*, share : Void*, attribs : Int32*) : Void*
  fun eglMakeCurrent(display : Void*, draw : Void*, read : Void*, context : Void*) : Int32
  fun eglGetProcAddress(name : UInt8*) : Void*
  fun eglDestroyContext(display : Void*, context : Void*) : Int32
  fun eglTerminate(display : Void*) : Int32
end

class DemoEGL
  getter display = Pointer(Void).null
  getter context = Pointer(Void).null

  def initialize(@es : Bool)
    platform_surfaceless = 0x31DD_u32
    @display = LibEGL.eglGetPlatformDisplay(platform_surfaceless, Pointer(Void).null, Pointer(Int32).null)
    raise "EGL: no surfaceless display" if @display.null?
    raise "EGL: initialization failed" if LibEGL.eglInitialize(@display, Pointer(Int32).null, Pointer(Int32).null) == 0
    api = @es ? 0x30A0_u32 : 0x30A2_u32
    raise "EGL: cannot bind API" if LibEGL.eglBindAPI(api) == 0

    renderable = @es ? 0x0040_i32 : 0x0008_i32
    config_attribs = [0x3040_i32, renderable, 0x3038_i32]
    config = Pointer(Void).null
    found = 0_i32
    LibEGL.eglChooseConfig(@display, config_attribs.to_unsafe, pointerof(config), 1_i32, pointerof(found))
    context_attribs = if @es
                        [0x3098_i32, 3_i32, 0x30FB_i32, 0_i32, 0x3038_i32]
                      else
                        [0x3098_i32, 4_i32, 0x30FB_i32, 3_i32, 0x30FD_i32, 1_i32, 0x3038_i32]
                      end
    @context = LibEGL.eglCreateContext(@display, config, Pointer(Void).null, context_attribs.to_unsafe)
    raise "EGL: context creation failed" if @context.null?
    empty = Pointer(Void).null
    unless LibEGL.eglMakeCurrent(@display, empty, empty, @context) != 0
      raise "EGL: cannot make surfaceless context current"
    end
  end

  def get_proc(name : UInt8*) : Void*
    LibEGL.eglGetProcAddress(name)
  end

  def close : Nil
    unless @context.null?
      LibEGL.eglDestroyContext(@display, @context)
      @context = Pointer(Void).null
    end
    unless @display.null?
      LibEGL.eglTerminate(@display)
      @display = Pointer(Void).null
    end
  end
end
