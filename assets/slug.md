# [GPU Methods for Text Rendering](https://maxcrofts.com/gpu-text-rendering/)

This past week Eric Lengyel [announced](https://terathon.com/blog/decade-slug.html) that he has dedicated the [Slug algorithm](https://sluglibrary.com/slug_algorithm.pdf) to the public domain. Back in 2020 while attending UQ I wrote a report for COSC3000 comparing three GPU text rendering methods, one of which was a rough implementation of the Slug algorithm. A mildly-edited version of that report is presented here.

- [20 Mar 2026](https://maxcrofts.com/gpu-text-rendering/)
- 2936 words
- [#gpu](https://maxcrofts.com/tags/gpu/) [#graphics](https://maxcrofts.com/tags/graphics/) [#typography](https://maxcrofts.com/tags/typography/)

## Introduction

Many 3D or otherwise graphically accelerated applications require text to be displayed to the user. Traditionally such applications have achieved this by rasterising the required characters/glyphs on the CPU, typically ahead of time. Often these glyphs will be combined into an atlas texture. However, given that screen resolutions are increasing with ever greater pixel densities, the limitations of atlas-based methods have begun to show. But is it practical to render glyphs on the GPU using standard font files? To that end, this report will compare three distinct methods applicable to this task: a stencil-based approach, an OpenGL extension implementing the former, and a fragment shader that samples the curve data directly. These methods have all been implemented as part of a rudimentary text file viewer, with the specific method being chosen at startup.

## Background

It is important to establish how fonts and the individual glyph outlines they contain are actually represented. An improved version of the prior TrueType format, OpenType has now become the de facto standard format for font files—even those with a `.ttf` extension. Glyph outlines within the format consist of a series of quadratic (TrueType) or cubic (PostScript) Bézier curves. Bézier curves are parametric equations that can model curves with theoretically infinite precision. The general form is given in Equation 1 where 𝐏i is the ith control point and n is the order of the curve.

𝐁(t)=∑i=0n(ni)(1−t)n−iti𝐏i(1)

Given their comparative ubiquity, this report is only concerned with TrueType curves. Equation 2 is the parametric equation representing a quadratic Bézier curve (i.e. a curve with three control points).

𝐁(t)=(1−t)2𝐏0+2(1−t)t𝐏1+t2𝐏2(2)

A glyph's outline can then be filled by calculating the winding number for every point contained within the glyph's bounding box. The winding number refers to the number of times a given point is enclosed by the outline—a positive integer indicates that the point is within the bounds of a curve (and should be filled) whereas a value of zero means that the point is outside the glyph.

## Methods

The following subsections detail GPU-based methods for rendering shapes defined by quadratic Bézier curves. Only the latter three have been implemented, the former is included as background to the second method.

### Resolution Independent Curve Rendering using Programmable Graphics Hardware

Loop and Blinn [1] presented a method for resolution independent rendering of paths, combining constrained Delaunay triangulation with a novel fragment shader. This shader leverages vertex attribute interpolation by assigning a particular set of texture coordinates for the three control points of each individual curve, these being: (0,0), (12,0), (1,1). These coordinates correspond to the unit parabola. The shader then evaluates Equation 3 where s and t are texture coordinates. If the resulting value is greater than zero, the fragment lies outside the bounds of the shape and should thus be discarded.

f(s,t)=s2−t(3)

### Resolution Independent Rendering of Deformable Vector Objects using Graphics Hardware

Kokojima et al. [2] devised a method of rendering 2D shapes on the GPU that required only minimal preprocessing from the CPU. This feature was a response to the contemporary popularity of technologies such as Flash where paths could be animated. In such instances, re-triangulating paths (as would be necessitated by prior methods) for every frame may prove to be costly. To address this, the method builds on the technique described in the OpenGL "Red Book" for rendering convex polygons using the stencil buffer [3]. With the stencil operation set to invert, drawing a fan of triangles comprised of adjacent points from the shape from an arbitrary origin will result in the buffer being filled with the desired path, effectively computing the shape's winding number. This result can then be written to the frame buffer using a simpler enclosing mesh such as a quad. Figure 1 depicts an example of such a triangulation, with triangle fans originating from the start of each contour. However the technique does not account for curved paths. By combining the stencil technique with a Loop and Blinn [1] quadratic discard shader (Appendix A), they were able to accurately render complex TrueType outlines [2].

![Example glyph triangulation](https://maxcrofts.com/gpu-text-rendering/kokojima_example.svg)

**Figure 1:** Example glyph triangulation

### GPU Accelerated Path Rendering

In 2012, Kilgard and Bolz [4] of NVIDIA Corporation presented an OpenGL vendor extension dubbed `NV_path_rendering` designed to draw vector shapes using the GPU. This rendering is performed in a manner that is similar to [2] but with added support for other curve types, including cubic Bézier curves. Curiously, this extension appears to encourage the use of OpenGL's legacy fixed functions. This stems from the extension's lack of interaction with the vertex pipeline. Instead, paths go through a distinct control point pipeline before rejoining at the fragment processing stage—this alternative pipeline does not have an analog to vertex shaders.

### GPU Centered Font Rendering Directly from Glyph Outlines

Citing the limitations of both atlas and geometry-based font rendering methods, Lengyel [5] explored the possibility of filling outlines using a specialised fragment shader—in effect, a shader that could sample the vector path in much the same way as a conventional texture, but with the added benefit of near infinite precision. While not the first time such an approach has been taken (one prior example is [6]), Lengyel's method does not suffer from robustness issues [5]. This is achieved by calculating the contribution of each curve to the winding number based on the signs of the y coordinates for each control point, observed relative to the position of the current fragment. As there are eight equivalence classes for such curves, a lookup table (Table 1) can be used to determine the curve's contribution. This table can be partially implemented as a series of bitwise operations (see `calculate_root_code` in Appendix B). While it is possible to use an integer based winding number, discarding fragments when zero, this would result in glyphs having harsh, aliased edges. Instead, the contribution can be used to calculate a fractional coverage value [5] (see `main` in Appendix B).

**Table 1:** Winding number contribution by curve equivalence class [5]

| **Class** | y2 | y1 | y0 | t1 | t0 |
| --- | --- | --- | --- | --- | --- |
| **A** | 0 | 0 | 0 | 0 | 0 |
| **B** | 0 | 0 | 1 | 0 | 1 |
| **C** | 0 | 1 | 0 | 1 | 1 |
| **D** | 0 | 1 | 1 | 0 | 1 |
| **E** | 1 | 0 | 0 | 1 | 0 |
| **F** | 1 | 0 | 1 | 1 | 1 |
| **G** | 1 | 1 | 0 | 1 | 0 |
| **H** | 1 | 1 | 1 | 0 | 0 |

This method does call for more preprocessing than the prior two. For a given fragment only a limited number of curves will end up making a contribution to the winding number with curves far away from the fragment having no impact. As such, each glyph is divided into a number of vertical and horizontal bands. Each fragment references the two bands it falls into (one in each direction) and then only calculates the contribution of all curves associated with that band. These bands may be of arbitrary width and each band is sorted to enable an early exit strategy, further reducing fragment processing.

## Implementation

To conduct this comparison, an application which allows users to view text files with arbitrary TrueType fonts was implemented. While the application is technically capable of handling dynamic text, adding an editing feature was deemed an unnecessary distraction from the goal of this report. The application was written in C++ against the OpenGL 4.1 core profile, with all shaders being written in the corresponding GLSL version 410. A number of extensions are also used where their presence proved beneficial, but the complementary vanilla code paths were left in place. To load TrueType files the public domain library `stb_truetype.h` was used, albeit wrapped in a C++ class. This class exposes an iterator for each glyph outline that returns all three control points per quadratic Bézier curve, with linear Bézier curves being losslessly converted to quadratic representations. SDL2 is used for window management while Glad is used to obtain OpenGL function pointers.

All buffers have their content generated on the CPU, with `std::vector` being used as a container. As a consequence of using this data structure, each buffer must consist solely of values of an identical type. The control points for all glyphs, should they be destined for either a vertex or texture buffer, are uploaded a single time at application start as a series of floating point values. Buffers that concern the specific text (e.g. glyph indices) are invalidated each frame. This is to reflect real world usage where text being displayed (e.g. as part of a menu in a video game) is often dynamic.

Given the intention of the application, an orthographic projection mapping pixels to OpenGL coordinates was used exclusively. How that matrix is used depends on the particular draw call. The combined use of `NV_path_rendering` and OpenGL's core profile necessitated that the projection and transformation matrices be multiplied together on the CPU for each rendered glyph as the fixed matrix functions (e.g. `glOrtho`) are not available in core. In the spirit of fair comparison, these calculations are maintained when using the method described by Kokojima et al, with a uniform buffer containing the matrix being updated before each glyph is drawn. For `NV_path_rendering`, the individual glyph draw calls are instead replaced with a single call to `glStencilFillPathInstancedNV`. However, both stencil code paths share the same coverage method.

A quad (consisting of two triangles) is drawn for each glyph that is the size of its bounds plus one extra pixel on all sides—this guarantees that the complete glyph is visible. The quad vertex shader accepts two attributes: a `vec2` indicating the current vertex position and a flat `vec4` containing the quad's colour. The latter attribute is included to prevent multiple draw calls when wanting to render multicoloured text. Although the application consistently sets this attribute to black, the vertex format is ultimately more reflective of real-world use cases. `NV_fill_rectangle` is used when available (given that all rendered quads are screen aligned) so as to avoid rendering two separate triangles and the resulting overdraw at the diagonal of the quad.

When Lengyel's method is used, the quads are drawn with an additional texture coordinate attribute and the appropriate shader is bound. Some liberties were taken when implementing this method. Unlike the canonical implementation, which uses two rectangular textures [7], this implementation opts for a single 1D buffer texture. Furthermore, both the layout and format of this buffer texture is different to either of the prescribed 2D textures. The former change is a consequence of shared control points being duplicated; this means that the indices used to address a particular glyph can be passed as vertex attributes without having to indicate changes in contour. However, this does mean that the band optimisation and thus the associated lookup texture have not been implemented. The decision was made due to the desire to avoid excessive preprocessing as well as there being some ambiguity as to how texture coordinates were to be mapped to their containing bands. This has certainly compromised shading performance for complex glyphs. Regarding Lengyel's use of a half precision format (`GL_RGBA16F`) for the curve texture, this choice appears as a storage optimisation rather than for performance reasons, given that the example shader code operates on single precision types [7]. As such the buffer texture used by this implementation used the `GL_RG32F` format with the red and green components respectively containing the x and y coordinates for each control point present in the font. The vertex shader implemented for this method (based on [7]) is listed in Appendix B.

## Results

Figure 2 compares the final version of each implemented method, rendering "Hello, world!" set in Times New Roman at a size of 48 pixels. While the results are similar, Lengyel's method produces a marginally sharper image.

![Kokojima et al.](https://maxcrofts.com/gpu-text-rendering/fixed16x_color.webp)

**(a)** Kokojima et al.

![Kilgard and Bolz](https://maxcrofts.com/gpu-text-rendering/kilgard16x_color.webp)

**(b)** Kilgard and Bolz

![Lengyel](https://maxcrofts.com/gpu-text-rendering/lengyel16x_color.webp)

**(c)** Lengyel

**Figure 2:** Comparison between methods rendered at 16x MSAA

Figure 3 compares the content of the stencil buffer between the initial versions of the manual and `NV_path_rendering` implementations at various levels of MSAA. Note that, for some unknown reason, while the serif appears to be missing from the 'r' in "world" in the output of `NV_path_rendering` it does appear in the final frame buffer.

![Manual stencil](https://maxcrofts.com/gpu-text-rendering/kokojima1x_stencil.webp)

**(a)** Manual stencil

![NV_path_rendering](https://maxcrofts.com/gpu-text-rendering/kilgard1x_stencil.webp)

**(b)** `NV_path_rendering`

![Manual stencil at 2x MSAA](https://maxcrofts.com/gpu-text-rendering/kokojima2x_stencil.webp)

**(c)** Manual stencil at 2x MSAA

![NV_path_rendering at 2x MSAA](https://maxcrofts.com/gpu-text-rendering/kilgard2x_stencil.webp)

**(d)** `NV_path_rendering` at 2x MSAA

![Manual stencil at 4x MSAA](https://maxcrofts.com/gpu-text-rendering/kokojima4x_stencil.webp)

**(e)** Manual stencil at 4x MSAA

![NV_path_rendering at 4x MSAA](https://maxcrofts.com/gpu-text-rendering/kilgard4x_stencil.webp)

**(f)** `NV_path_rendering` at 4x MSAA

![Manual stencil at 8x MSAA](https://maxcrofts.com/gpu-text-rendering/kokojima8x_stencil.webp)

**(g)** Manual stencil at 8x MSAA

![NV_path_rendering at 8x MSAA](https://maxcrofts.com/gpu-text-rendering/kilgard8x_stencil.webp)

**(h)** `NV_path_rendering` at 8x MSAA

![Manual stencil at 16x MSAA](https://maxcrofts.com/gpu-text-rendering/kokojima16x_stencil.webp)

**(i)** Manual stencil at 16x MSAA

![NV_path_rendering at 16x MSAA](https://maxcrofts.com/gpu-text-rendering/kilgard16x_stencil.webp)

**(j)** `NV_path_rendering` at 16x MSAA

**Figure 3:** Stencil buffer content for the initial stencil implementations

![Manual stencil](https://maxcrofts.com/gpu-text-rendering/kokojima16x_color.webp)

**(a)** Manual stencil

![NV_path_rendering](https://maxcrofts.com/gpu-text-rendering/kilgard16x_color.webp)

**(b)** `NV_path_rendering`

**Figure 4:** Comparison between the initial stencil implementations at 16x MSAA

It can be observed in Figure 3 that `NV_path_rendering` appears to be making more effective use of the additional samples afforded by MSAA than the manual implementation. This disparity was addressed by increasing the shading rate for the stencil draw calls using the `ARB_sample_shading` extension. While the two renders are still not strictly identical (see Figure 2), the differences have become practically unnoticeable. This newfound precision also allowed for the points to be shared between the triangle fan and the quadratic hulls—when this optimisation was attempted beforehand artifacts would appear extending from the origin of the fan.

To evaluate each implementation's performance a body of random text sufficient to cover a 1080p frame buffer was generated using [8]. The total number of glyphs were gradually increased (i.e. initially only the first 100 characters of the text were drawn) and approximate frame timings were measured at 16x MSAA on a NVIDIA GeForce GTX1070 using nSight's overlay. These timings are listed in Table 2. Note that the glyph counts do include whitespace. This text was typeset in Arial, as it is one of the most commonly used fonts, at a size of 16 pixels to test legibility at smaller sizes. Specimens containing the entire text as rendered by each method can be found in Appendices C through E.

**Table 2:** Approximate frame timings in milliseconds

| **Glyphs** | **Kokojima et al.** | **Kilgard and Bolz** | **Lengyel** (no band texture) |
| --- | --- | --- | --- |
| 100 | 0.80 | 0.75 | 0.75 |
| 500 | 1.10 | 0.95 | 1.05 |
| 1000 | 1.60 | 1.17 | 1.60 |
| 5000 | 4.66 | 2.93 | 12.66 |
| 10000 | 8.44 | 5.66 | 43.70 |
| 15914 | 13.9 | 8.33 | 105.3 |

Given that the band texture optimisation was left unimplemented, it was expected that Lengyel's method would perform the slowest. However, the implementation's performance proved to be on par with the other two when drawing 1000 characters or less. The performance of `NV_path_rendering` is approximately 1.75 times faster than the manual stencil implementation on average. Given this disparity, it would be worth exploring newer versions of OpenGL, or alternative APIs such as Vulkan, that allow for reduced driver overhead. An alternative hypothesis would be that `NV_path_rendering` only uses an enhanced shading rate for triangles containing the curves themselves as the majority of each glyph would not benefit from the additional precision. All methods produced legible text, although Lengyel's method did appear to have some issues with subpixel positioning, resulting in inconsistent stroke intensity.

## Conclusions

This report confirms that rendering text directly on the GPU is a viable approach, with all three methods proving workable. The reduced driver overhead of `NV_path_rendering` is apparent when compared with manually implementing the method described by Kokojima et al. However, the manual approach makes more sense if a modern programmable graphics pipeline is used—the control points of paths drawn with `NV_path_rendering` cannot be processed using vertex shaders. Additionally, as it is a vendor extension that was never standardised, not all hardware supports it.

While Lengyel's approach is more complex, it does have its benefits. One such advantage is that it enables the direct sampling of vector shapes without an intermediary buffer, meaning there is greater flexibility as to what the final fragment can evaluate to when compared to the stencil methods. The fact that it does not require the stencil buffer at all makes it unique among the three approaches.

## Future Work

Due to this report's focus on working with shape data directly on the GPU, the results lack a suitable control; for instance, frame timings for an atlas-based approach. Establishing a baseline for performance comparison between vector methods and traditional textures would be useful. Beyond that, the implementation of Lengyel's method produced for this report did not optimise the curve lookup procedure and thus suffered from degraded performance. This could be remedied by using Lengyel's own commercial implementation [9] of the approach.

Because Lengyel's approach allows for the vector path to be effectively sampled, alternative anti-aliasing methods would not be difficult to experiment with. Perhaps type hinting information could also be incorporated to increase glyph legibility at small font sizes.

This report does not explore the complexity of using each method within a 3D environment. Lengyel's method is likely to be the most straightforward to integrate as it is applicable to arbitrary geometry.

## Appendix A: Quadratic Discard Shader

```
#version 410 core

in vec2 vTexCoord;

void main()
{
	if (vTexCoord.x * vTexCoord.x - vTexCoord.y > 0.0) {
		discard;
	}
}
```

## Appendix B: Curve Coverage Shader

```
// Based on Eric Lengyel's presentation at i3D 2018
// Available at: http://terathon.com/i3d2018_lengyel.pdf

#version 410 core

in vec2 vTexCoord;
flat in vec4 vColor;
flat in uvec2 vIndex;

out vec4 fColor;

uniform samplerBuffer uCurveTex;

vec2 solve( vec2 p0, vec2 p1, vec2 p2 )
{
	// Calculate coefficients
	vec2 a = p0 - p1 * 2.0 + p2;
	vec2 b = p0 - p1;
	float ra = 1.0 / a.y;
	float rb = 0.5 / b.y;

	// Ensure discriminant is greater than zero
	float d = sqrt( max( b.y * b.y - a.y * p0.y, 0.0 ) );

	float t1 = ( b.y - d ) * ra;
	float t2 = ( b.y + d ) * ra;

	// Linear case
	if ( abs( a.y ) < 0.0001 ) {
		t1 = t2 = p0.y * rb;
	}

	return vec2( ( a.x * t1 - b.x * 2.0 ) * t1 + p0.x, ( a.x * t2 - b.x * 2.0 ) * t2 + p0.x );
}

ivec2 calculate_root_code( float y1, float y2, float y3 )
{
	int a = floatBitsToInt( y1 );
	int b = floatBitsToInt( y2 );
	int c = floatBitsToInt( y3 );
	return ivec2( ~a & ( b | c ) | ( ~b & c ), a & ( ~b | ~c ) | ( b & ~c ) );
}

void main()
{
	vec2 pixelsPerEm = vec2( 1.0 / fwidth( vTexCoord.x ), 1.0 / fwidth( vTexCoord.y ) );

	float coverage = 0.0;

	for ( int curve = int( vIndex.x ); curve < int( vIndex.y ); curve += 3 ) {
		vec2 p0 = texelFetch( uCurveTex, curve + 0 ).xy - vTexCoord;
		vec2 p1 = texelFetch( uCurveTex, curve + 1 ).xy - vTexCoord;
		vec2 p2 = texelFetch( uCurveTex, curve + 2 ).xy - vTexCoord;

		ivec2 code = calculate_root_code( p0.y, p1.y, p2.y );

		if ( ( code.x | code.y ) < 0 ) {
			vec2 root = solve( p0, p1, p2 ) * pixelsPerEm;

			if ( code.x < 0 && root.x > 0.0 ) {
				// Increase coverage
				coverage += clamp( root.x, 0.0, 1.0 );
			}

			if ( code.y < 0 && root.y > 0.0 ) {
				// Decrease coverage
				coverage -= clamp( root.y, 0.0, 1.0 );
			}
		}
	}

	fColor = vec4( vColor.xyz, vColor.a * coverage );
}
```

## Appendix C: Kokojima et al. Result

![image](https://maxcrofts.com/gpu-text-rendering/kokojima.webp)

## Appendix D: Kilgard and Bolz Result

![image](https://maxcrofts.com/gpu-text-rendering/kilgard.webp)

## Appendix E: Lengyel Result

![image](https://maxcrofts.com/gpu-text-rendering/lengyel.webp)

## References

1. C. Loop and J. Blinn, “Resolution Independent Curve Rendering using Programmable Graphics Hardware,” *ACM SIGGRAPH 2005 Papers*, pp. 1000–1009, 2005.
2. Y. Kokojima, K. Sugita, T. Saito, and T. Takemoto, “Resolution Independent Rendering of Deformable Vector Objects using Graphics Hardware,” *ACM SIGGRAPH 2006 Sketches*, p. 118, 2006.
3. M. Woo, J. Neider, and T. Davis, “The Official Guide to Learning OpenGL, Version 1.1,” 1997, ch. 14.
4. M. J. Kilgard and J. Bolz, “GPU-accelerated path rendering,” *ACM Transactions on Graphics (TOG)*, vol. 31, no. 6, 2012.
5. E. Lengyel, “GPU-Centered Font Rendering Directly from Glyph Outlines,” *Journal of Computer Graphics Techniques (JCGT)*, vol. 6, no. 2, pp. 31–47, 2017.
6. W. Dobbie, “GPU text rendering with vector textures.” Accessed: Jun. 03, 2020. [Online]. Available: [http://wdobbie.com/post/gpu-text-rendering-with-vector-textures/](http://wdobbie.com/post/gpu-text-rendering-with-vector-textures/)
7. E. Lengyel, “GPU-Centered Font Rendering Directly from Glyph Outlines.” Accessed: Jun. 03, 2020. [Online]. Available: [http://terathon.com/i3d2018_lengyel.pdf](http://terathon.com/i3d2018_lengyel.pdf)
8. “Lorem Ipsum - All the facts - Lipsum generator.” Accessed: Jun. 04, 2020. [Online]. Available: [https://www.lipsum.com/](https://www.lipsum.com/)
9. Terathon Software, “Slug Font Rendering Library.” Accessed: Jun. 05, 2020. [Online]. Available: [https://sluglibrary.com/](https://sluglibrary.com/)
