// Vertex shader

struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) tex: vec2<f32>,
    @location(2) fg_color: vec4<f32>,
    @location(3) alt_color: vec4<f32>,
    @location(4) hsv: vec3<f32>,
    @location(5) has_color: f32,
    @location(6) mix_value: f32,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) tex: vec2<f32>,
    @location(1) fg_color: vec4<f32>,
    @location(2) alt_color: vec4<f32>,
    @location(3) hsv: vec3<f32>,
    @location(4) has_color: f32,
    @location(5) mix_value: f32,
};

struct ShaderUniform {
  foreground_text_hsb: vec3<f32>,
  milliseconds: u32,
  projection: mat4x4<f32>,
};
@group(0) @binding(0) var<uniform> uniforms: ShaderUniform;

@group(1) @binding(0) var atlas_linear_tex: texture_2d<f32>;
@group(1) @binding(1) var atlas_linear_sampler: sampler;

@group(2) @binding(0) var atlas_nearest_tex: texture_2d<f32>;
@group(2) @binding(1) var atlas_nearest_sampler: sampler;

fn rgb2hsv(c: vec3<f32>) -> vec3<f32>
{
    let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    let p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));

    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32>
{
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3(0.0), vec3(1.0)), c.y);
}

fn apply_hsv(c: vec4<f32>, transform: vec3<f32>) -> vec4<f32>
{
  let hsv = rgb2hsv(c.rgb) * transform;
  return vec4<f32>(hsv2rgb(hsv).rgb, c.a);
}

@vertex
fn vs_main(
    model: VertexInput,
) -> VertexOutput {
    var out: VertexOutput;
    out.tex = model.tex;
    out.fg_color = model.fg_color;
    out.alt_color = model.alt_color;
    out.hsv = model.hsv;
    out.has_color = model.has_color;
    out.mix_value = model.mix_value;
    out.clip_position = uniforms.projection * vec4<f32>(model.position, 0.0, 1.0);
    return out;
}

// Fragment shader

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
  var fg_color: vec4<f32> = mix(in.fg_color, in.alt_color, in.mix_value);
  var color: vec4<f32> = fg_color;
  var linear_tex: vec4<f32> = textureSample(atlas_linear_tex, atlas_linear_sampler, in.tex);
  var nearest_tex: vec4<f32> = textureSample(atlas_nearest_tex, atlas_nearest_sampler, in.tex);

  if in.has_color == 3.0 {
    // Solid color block
  } else if in.has_color == 2.0 {
    // Window background attachment
    // Apply window_background_image_opacity to the background image
    color = linear_tex;
    color.a *= fg_color.a;
  } else if in.has_color == 1.0 {
    // the texture is full color info (eg: color emoji glyph)
    color = nearest_tex;
  } else if in.has_color == 4.0 {
    // Grayscale poly quad for non-aa text render layers
    color = fg_color;
    color.a *= nearest_tex.a;
  } else if in.has_color == 0.0 {
    // the texture is the alpha channel/color mask
    // and we need to tint with the fg_color
    color = fg_color;
    color.a = nearest_tex.a;
    color = apply_hsv(color, uniforms.foreground_text_hsb);
  }

  color = apply_hsv(color, in.hsv);

  // We MUST output SRGB and tell glium that we do that (outputs_srgb),
  // otherwise something in glium over-gamma-corrects depending on the gl setup.
  // color = to_srgb(color);

  return color;
}
