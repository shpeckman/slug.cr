# examples/glfw.cr

@[Link("glfw")]
lib LibGLFW
  fun glfwInit : Int32
  fun glfwTerminate : Nil
  fun glfwWindowHint(hint : Int32, value : Int32) : Nil
  fun glfwCreateWindow(width : Int32, height : Int32, title : UInt8*, monitor : Void*, share : Void*) : Void*
  fun glfwDestroyWindow(window : Void*) : Nil
  fun glfwMakeContextCurrent(window : Void*) : Nil
  fun glfwSwapInterval(interval : Int32) : Nil
  fun glfwWindowShouldClose(window : Void*) : Int32
  fun glfwSwapBuffers(window : Void*) : Nil
  fun glfwPollEvents : Nil
  fun glfwGetFramebufferSize(window : Void*, width : Int32*, height : Int32*) : Nil
  fun glfwGetProcAddress(name : UInt8*) : Void*
end

class DemoGLFW
  getter window = Pointer(Void).null

  def initialize(@es : Bool, width : Int32, height : Int32)
    raise "GLFW: initialization failed" if LibGLFW.glfwInit == 0
    if @es
      LibGLFW.glfwWindowHint(0x00022001_i32, 0x00030002_i32)
      LibGLFW.glfwWindowHint(0x00022002_i32, 3_i32)
      LibGLFW.glfwWindowHint(0x00022003_i32, 0_i32)
    else
      LibGLFW.glfwWindowHint(0x00022001_i32, 0x00030001_i32)
      LibGLFW.glfwWindowHint(0x00022002_i32, 4_i32)
      LibGLFW.glfwWindowHint(0x00022003_i32, 3_i32)
      LibGLFW.glfwWindowHint(0x00022008_i32, 0x00032001_i32)
    end
    title = @es ? "Slug - OpenGL ES" : "Slug - OpenGL"
    @window = LibGLFW.glfwCreateWindow(width, height, title, Pointer(Void).null, Pointer(Void).null)
    if @window.null?
      LibGLFW.glfwTerminate
      raise "GLFW: window creation failed"
    end
    LibGLFW.glfwMakeContextCurrent(@window)
    LibGLFW.glfwSwapInterval(1_i32)
  end

  def get_proc(name : UInt8*) : Void*
    LibGLFW.glfwGetProcAddress(name)
  end

  def close : Nil
    LibGLFW.glfwDestroyWindow(@window) unless @window.null?
    @window = Pointer(Void).null
    LibGLFW.glfwTerminate
  end
end
