#ifdef GL_ES
#extension GL_EXT_draw_buffers: enable
precision highp float;
#endif

uniform vec3 uLightDir;
uniform vec3 uCameraPos;
uniform vec3 uLightRadiance;
uniform sampler2D uGDiffuse;
uniform sampler2D uGDepth;
uniform sampler2D uGNormalWorld;
uniform sampler2D uGShadow;
uniform sampler2D uGPosWorld;

varying mat4 vWorldToScreen;
varying highp vec4 vPosWorld;

#define M_PI 3.1415926535897932384626433832795
#define TWO_PI 6.283185307
#define INV_PI 0.31830988618
#define INV_TWO_PI 0.15915494309
#define SAMPLE_NUM 3

float Rand1(inout float p) {
  p = fract(p * .1031);
  p *= p + 33.33;
  p *= p + p;
  return fract(p);
}

vec2 Rand2(inout float p) {
  return vec2(Rand1(p), Rand1(p));
}

float InitRand(vec2 uv) {
  vec3 p3 = fract(vec3(uv.xyx) * .1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}


vec4 Project(vec4 a) {
  return a / a.w;
}

float GetDepth(vec3 posWorld) {
  float depth = (vWorldToScreen * vec4(posWorld, 1.0)).w;
  return depth;
}

/*
 * Transform point from world space to screen space([0, 1] x [0, 1])
 *
 */
vec2 GetScreenCoordinate(vec3 posWorld) {
  vec2 uv = Project(vWorldToScreen * vec4(posWorld, 1.0)).xy * 0.5 + 0.5;
  return uv;
}
vec3 GetScreenCoordinate3D(vec3 posWorld) {
  //为什么vWorldToScreen.z==vWorldToScreen.w==depth???
  vec4 translatedCoord = vWorldToScreen * vec4(posWorld, 1.0);
  vec3 result = vec3(translatedCoord.xy / translatedCoord.z * 0.5 + 0.5, translatedCoord.z);
  return result;
}
vec3 GetScreenVector(vec3 vectorWorld) {
  vec4 translatedVector = vWorldToScreen * vec4(vectorWorld, 0.0);
  return vec3(translatedVector.xy / translatedVector.z, translatedVector.z);
}

float GetGBufferDepth(vec2 uv) {
  float depth = texture2D(uGDepth, uv).x;
  if(depth < 1e-2) {
    depth = 1000.0;
  }
  return depth;
}

vec3 GetGBufferNormalWorld(vec2 uv) {
  vec3 normal = texture2D(uGNormalWorld, uv).xyz;
  return normal;
}

vec3 GetGBufferPosWorld(vec2 uv) {
  vec3 posWorld = texture2D(uGPosWorld, uv).xyz;
  return posWorld;
}

float GetGBufferuShadow(vec2 uv) {
  float visibility = texture2D(uGShadow, uv).x;
  return visibility;
}

vec3 GetGBufferDiffuse(vec2 uv) {
  vec3 diffuse = texture2D(uGDiffuse, uv).xyz;
  diffuse = pow(diffuse, vec3(2.2));
  return diffuse;
}

/*
 * Evaluate diffuse bsdf value.
 *
 * wi, wo are all in world space.
 * uv is in screen space, [0, 1] x [0, 1].
 *
 */
vec3 EvalDiffuse(vec3 wo, vec2 uv) {
  //wo是光源方向
  vec3 L = GetGBufferDiffuse(uv) / M_PI * max(dot(wo, GetGBufferNormalWorld(uv)), 0.0);
  return L;
}

/*
 * Evaluate directional light with shadow map
 * uv is in screen space, [0, 1] x [0, 1].
 *
 */
vec3 EvalDirectionalLight(vec2 uv) {
  vec3 wo = uLightDir;
  vec3 Le = uLightRadiance * EvalDiffuse(wo,uv) * GetGBufferuShadow(uv);
  return Le;
}




void main() {
  vec2 screenCoord = GetScreenCoordinate(vPosWorld.xyz);
  vec3 normal = normalize(GetGBufferNormalWorld(screenCoord));
  vec3 wi = normalize(uCameraPos - GetGBufferPosWorld(screenCoord));
  vec3 L;
  if(dot(wi,normal)>0.0){
    L = EvalDirectionalLight(screenCoord);
  }else{
    L= vec3(0.0,0.0,0.0);
  }
  gl_FragData[0] = vec4(L, 1.0);
}
