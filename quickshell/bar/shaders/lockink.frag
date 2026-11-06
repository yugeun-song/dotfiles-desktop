#version 440
// The lock screen's ink (modules/LockInk.qml), per pixel: what an element
// draws, recoloured against what lies under that very pixel on the screen,
// live, so that over a video too nothing goes the colour of its ground (the
// user, 2026-11-06: an "S" may take one colour at its top and another at its
// foot). The rules are hypr/scripts/lock-colours.py's, which hyprlock's
// fallback still takes per group from the still wallpaper: the bar's beige
// wherever it reads (3:1), else a deep tone of the hue opposite the ground's
// (the bar's own hue under a grey), dark enough to reach 4.5:1; a soft halo
// of the other tone where the chosen ink still reads poorly; a surface's
// pane a faint white where the beige reads through it, else as dark as lets
// it read, and frosted white under the dark ink. Keep the two in step.
//
// mode 0: an element's ink, its alpha kept and its colour replaced.
// mode 1: a surface, its pane drawn in red and its edge in green (one
// layer, two masks), each given its colour and strength here.
// Compile with shaders/build.sh; the .qsb beside this file is what loads.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // The layer's rectangle in the screen's 0..1 space, to find the ground.
    vec4 area;
    // The light ink, opaque.
    vec4 beige;
    // One item pixel in the layer's 0..1 space, and the halo's reach in
    // pixels (0: none).
    vec2 px;
    float haloSize;
    float mode;
};

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D under;

// The bar's background's hue in OKLab (a, b), unit length: the dark's hue
// over a grey ground.
const vec2 BAR = vec2(0.09378, -0.99559);
const float READS = 3.0;
const float TARGET = 4.5;

vec3 toLinear(vec3 c)
{
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 toStored(vec3 c)
{
    c = clamp(c, 0.0, 1.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

float encode1(float v)
{
    v = clamp(v, 0.0, 1.0);
    return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1.0 / 2.4) - 0.055;
}

float decode1(float v)
{
    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4);
}

float luma(vec3 lin)
{
    return dot(lin, vec3(0.2126, 0.7152, 0.0722));
}

float cbrt(float x)
{
    return sign(x) * pow(abs(x), 1.0 / 3.0);
}

vec3 oklab(vec3 c)
{
    float l = cbrt(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b);
    float m = cbrt(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b);
    float s = cbrt(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b);
    return vec3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
}

vec3 fromLab(vec3 lab)
{
    float l = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
    float m = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
    float s = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
    l = l * l * l;
    m = m * m * m;
    s = s * s * s;
    return vec3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
}

// The dark over this ground: opposite its hue, chroma growing with the
// ground's, as light as still reaches TARGET (0.40 to 0.14 in OKLab), its
// chroma cut back until sRGB holds it.
vec3 darkFor(vec3 ground, float y)
{
    vec3 lab = oklab(ground);
    float chroma = length(lab.yz);
    float w = clamp((chroma - 0.005) / 0.015, 0.0, 1.0);
    vec2 dir = -w * lab.yz / max(chroma, 1e-6) + (1.0 - w) * BAR;
    float n = length(dir);
    dir = n < 1e-6 ? BAR : dir / n;
    float c = 0.04 + 0.06 * min(chroma, 0.1) / 0.1;
    float lightness = clamp(cbrt(max(0.0, (y + 0.05) / TARGET - 0.05)), 0.14, 0.40);
    vec3 lin = fromLab(vec3(lightness, dir * c));
    for (int i = 0; i < 4; i++) {
        if (all(greaterThanEqual(lin, vec3(-1e-4))) && all(lessThanEqual(lin, vec3(1.0001))))
            break;
        c *= 0.7;
        lin = fromLab(vec3(lightness, dir * c));
    }
    return clamp(lin, 0.0, 1.0);
}

void main()
{
    vec4 s = texture(source, qt_TexCoord0);
    vec3 ground = toLinear(texture(under, area.xy + qt_TexCoord0 * area.zw).rgb);
    float y = luma(ground);
    vec3 light = toLinear(beige.rgb);
    float yLight = luma(light);
    vec3 dark = darkFor(ground, y);
    float yDark = luma(dark);
    float cl = (yLight + 0.05) / (y + 0.05);
    float cd = (y + 0.05) / (yDark + 0.05);
    // 0 the beige, 1 the dark: the beige wherever it reads or reads better,
    // over a narrow band, so a glyph across the line shades, not cuts.
    float t = (1.0 - smoothstep(READS - 0.4, READS + 0.4, cl)) * smoothstep(-0.3, 0.3, cd - cl);
    vec3 ink = mix(light, dark, t);

    if (mode < 0.5) {
        vec3 shown = toStored(ink);
        vec4 out_ = vec4(shown * s.a, s.a);
        if (haloSize > 0.0) {
            float reach = mix(cl, cd, t);
            float need = smoothstep(READS + 0.2, READS - 0.8, reach);
            if (need > 0.0) {
                float spread = 0.0;
                for (int i = 0; i < 12; i++) {
                    float a = 6.2831853 * float(i) / 12.0;
                    vec2 d = vec2(cos(a), sin(a)) * px * haloSize;
                    spread += texture(source, qt_TexCoord0 + d).a + texture(source, qt_TexCoord0 + d * 0.5).a;
                }
                float h = need * 0.65 * clamp(spread / 12.0, 0.0, 1.0) * (1.0 - s.a);
                // Black round the beige, white round the dark.
                vec3 glow = vec3(t);
                out_ += vec4(glow * h, h);
            }
        }
        fragColor = out_ * qt_Opacity;
        return;
    }

    // A surface. Under the beige: the faint white while the beige reads
    // through it (ground up to 0.104), else dark, thick enough to bring the
    // ground to 0.148, 15 to 70%. Under the dark: frosted white, thick
    // enough to bring it up to where the dark reads, 45 to 90%.
    float e = encode1(y);
    float darkA = clamp(1.0 - 0.42 / max(e, 1e-4), 0.15, 0.70);
    float faint = smoothstep(0.090, 0.118, y);
    vec4 paneLight = mix(vec4(1.0, 1.0, 1.0, 0.10), vec4(0.0, 0.0, 0.0, darkA), faint);
    vec4 edgeLight = mix(vec4(1.0, 1.0, 1.0, 0.20), vec4(1.0, 1.0, 1.0, 0.12), faint);
    float need = encode1(TARGET * (yDark + 0.05) - 0.05);
    float frostA = clamp((need - e) / max(1.0 - e, 1e-4), 0.45, 0.90);
    vec4 paneDark = vec4(1.0, 1.0, 1.0, frostA);
    vec4 edgeDark = vec4(toStored(dark), 0.14);
    vec4 pane = mix(paneLight, paneDark, t);
    vec4 edge = mix(edgeLight, edgeDark, t);
    // The pane runs under the edge; the edge lies over it.
    float pa = pane.a * (s.r + s.g);
    float ea = edge.a * s.g;
    fragColor = vec4(edge.rgb * ea + pane.rgb * pa * (1.0 - ea), ea + pa * (1.0 - ea)) * qt_Opacity;
}
