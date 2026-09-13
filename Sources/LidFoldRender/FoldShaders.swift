import Foundation

/// The fold, drawn in a single full-screen fragment pass.
///
/// Every glass pixel maps back into the frozen picture through the inverse
/// perspective transform computed on the CPU. The picture lives on a black
/// margin inside one mipmapped texture (a Gaussian pyramid sits over it),
/// so blur is a handful of trilinear taps at a mip level chosen per pixel.
/// Darkening scales with that same distance-from-the-hinge value.
public enum FoldShaders {
    public static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4 column0;          // screen -> picture, column 0 in xyz
        float4 column1;
        float4 column2;
        float4 screenAndOrigin;  // screen size (pt), padded origin (pt)
        float4 paddedAndBlur;    // padded size (pt), max radius (px), blur strength
        float4 shape;            // max dim, pixel scale, max mip level, dim strength
        float4 more;             // dim reach, picture top edge on the glass, unused, unused
    };

    struct PadUniforms {
        float4 inset; // inset in pixels (x, y), frame size in pixels (z, w)
    };

    // Copies a captured frame into the padded texture's centre; the
    // margin is left black so frost can dissolve the picture's edges into
    // the dark rather than cutting them off.
    fragment float4 padFragment(float4 position [[position]],
                                constant PadUniforms &u [[buffer(0)]],
                                texture2d<float> frame [[texture(0)]]) {
        constexpr sampler edge(filter::linear, address::clamp_to_edge);
        float2 uv = (position.xy - u.inset.xy) / u.inset.zw;
        if (any(uv < 0.0) || any(uv > 1.0)) { return float4(0.0, 0.0, 0.0, 1.0); }
        return float4(frame.sample(edge, uv).rgb, 1.0);
    }

    vertex float4 foldVertex(uint id [[vertex_id]]) {
        const float2 corners[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
        return float4(corners[id], 0.0, 1.0);
    }

    fragment float4 foldFragment(float4 position [[position]],
                                 constant Uniforms &u [[buffer(0)]],
                                 texture2d<float> picture [[texture(0)]]) {
        constexpr sampler smooth(filter::linear, mip_filter::linear, address::clamp_to_edge);

        const float2 screenSize   = u.screenAndOrigin.xy;
        const float2 paddedOrigin = u.screenAndOrigin.zw;
        const float2 paddedSize   = u.paddedAndBlur.xy;
        const float  maxRadius    = u.paddedAndBlur.z;
        const float  blurStrength = u.paddedAndBlur.w;
        const float  maxDim       = u.shape.x;
        const float  pixelScale   = u.shape.y;
        const float  maxLevel     = u.shape.z;
        const float  dimStrength  = u.shape.w;
        const float  dimReach     = u.more.x;
        const float  topEdge      = u.more.y;

        // Fragments are pixels with y down; the geometry is points with y up.
        float2 screenPoint = float2(position.x / pixelScale, screenSize.y - position.y / pixelScale);
        // Above the picture's far edge the glass carries that edge's own
        // light, fading out in screen space, so there is never a hard
        // seam where the picture runs out.
        float above = max(screenPoint.y - (topEdge - 2.0), 0.0);
        screenPoint.y = min(screenPoint.y, topEdge - 2.0);

        float3x3 toPicture = float3x3(u.column0.xyz, u.column1.xyz, u.column2.xyz);
        float3 mapped = toPicture * float3(screenPoint, 1.0);
        if (abs(mapped.z) < 1e-6 || mapped.z < 0.0) { return float4(0.0, 0.0, 0.0, 1.0); }
        float2 picturePoint = mapped.xy / mapped.z;

        float2 unit = (picturePoint - paddedOrigin) / paddedSize;
        if (any(unit < 0.0) || any(unit > 1.0)) { return float4(0.0, 0.0, 0.0, 1.0); }
        float2 clampedPoint = clamp(picturePoint, float2(0.0), screenSize);
        float2 texCoord = float2(unit.x, 1.0 - unit.y);

        // Distance from the hinge, 0...1, measured in the frozen picture's own frame.
        float g = clamp(clampedPoint.y / screenSize.y, 0.0, 1.0);

        // Blur grows with that distance, so the top blurs away first
        // while pixels near the hinge stay sharp the longest.
        float radius = blurStrength * g * maxRadius;
        float mip = clamp(log2(max(radius, 1.0)), 0.0, maxLevel);

        float3 colour;
        if (radius < 0.75) {
            colour = picture.sample(smooth, texCoord, level(0.0)).rgb;
        } else {
            float2 texel = 1.0 / (paddedSize * pixelScale);
            float2 stride = texel * radius * 0.45;
            colour = float3(0.0);
            const float weights[3] = { 1.0, 2.0, 1.0 };
            for (int y = -1; y <= 1; y++) {
                for (int x = -1; x <= 1; x++) {
                    float w = weights[x + 1] * weights[y + 1] / 16.0;
                    colour += picture.sample(smooth, texCoord + float2(x, y) * stride, level(mip)).rgb * w;
                }
            }
        }

        // Dimming in linear light, so the far edge fades to black instead of grey.
        float spread = smoothstep(0.0, dimReach, g);
        float dim = dimStrength * spread * maxDim;
        colour *= pow(1.0 - dim, 2.1);
        colour *= exp(-pow(above / max(0.22 * screenSize.y, 1.0), 1.4));

        return float4(max(colour, 0.0), 1.0);
    }
    """
}
