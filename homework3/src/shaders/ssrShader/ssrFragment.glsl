#ifdef GL_ES
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
uniform sampler2D uGDirectLight;
uniform vec2 resolution;

varying mat4 vWorldToScreen;
varying highp vec4 vPosWorld;

#define M_PI 3.1415926535897932384626433832795
#define TWO_PI 6.283185307
#define INV_PI 0.31830988618
#define INV_TWO_PI 0.15915494309
#define SAMPLE_NUM 6

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

vec3 SampleHemisphereUniform(inout float s, out float pdf) {
  vec2 uv = Rand2(s);
  float z = uv.x;
  float phi = uv.y * TWO_PI;
  float sinTheta = sqrt(1.0 - z * z);
  vec3 dir = vec3(sinTheta * cos(phi), sinTheta * sin(phi), z);
  pdf = INV_TWO_PI;
  return dir;
}

vec3 SampleHemisphereCos(inout float s, out float pdf) {
  vec2 uv = Rand2(s);
  float z = sqrt(1.0 - uv.x);
  float phi = uv.y * TWO_PI;
  float sinTheta = sqrt(uv.x);
  vec3 dir = vec3(sinTheta * cos(phi), sinTheta * sin(phi), z);
  pdf = z * INV_PI;
  return dir;
}

void LocalBasis(vec3 n, out vec3 b1, out vec3 b2) {
  float sign_ = sign(n.z);
  if(n.z == 0.0) {
    sign_ = 1.0;
  }
  float a = -1.0 / (sign_ + n.z);
  float b = n.x * n.y * a;
  b1 = vec3(1.0 + sign_ * n.x * n.x * a, sign_ * b, -sign_ * n.x);
  b2 = vec3(b, sign_ + n.y * n.y * a, -n.y);
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

vec3 GetGBufferDirectLight(vec2 uv) {
  vec3 directLight = texture2D(uGDirectLight, uv).xyz;
  return directLight;
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
bool RayMarchScreenSpace(vec3 ori, vec3 dir, out vec3 hitPos) {
  //ori和dir都是世界坐标，返回的hitpos是图像空间坐标，带depth所以是vec3
  vec3 screenSpaceOri = GetScreenCoordinate3D(ori);
  vec3 screenSpaceDir = GetScreenVector(dir);
  //resolution.x and resolution.y is the width and height of display
  vec3 step;
  if(abs(screenSpaceDir.x * resolution.x) > abs(screenSpaceDir.y * resolution.y)) {
    step = vec3(1.0, screenSpaceDir.yz / screenSpaceDir.x) / resolution.x;
  } else {
    step = vec3(screenSpaceDir.x / screenSpaceDir.y, 1.0, screenSpaceDir.z / screenSpaceDir.y) / resolution.y;
  }
  vec3 tracePoint = screenSpaceOri + step;
  //march across screen space, not accurate
  //int maxStep = int(max(resolution.x, resolution.y));
  const int maxStep = 500;
  for(int count = 0; count < maxStep; count++) {
    if(tracePoint.z < GetGBufferDepth(tracePoint.xy)) {
      hitPos = tracePoint;
      return true;
    }
    tracePoint += step;
  }
  return false;
}
bool RayMarch(vec3 ori, vec3 dir, out vec3 hitPos) {

  const float stepLength = 0.09;
  vec3 step = dir * stepLength;
  vec3 tracePoint = ori + step;
  const int maxStep = 80;
  const float maxDis = 0.15;
  for(int count = 0; count < maxStep; count++) {
    float deltaZ = GetDepth(tracePoint) - GetGBufferDepth(GetScreenCoordinate(tracePoint));
    if(deltaZ >= 0.0 && deltaZ < maxDis) {
      hitPos = tracePoint;
      return true;
    }
    tracePoint += step;
  }

  return false;
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
  vec3 L = GetGBufferDiffuse(uv) * max(dot(wo, GetGBufferNormalWorld(uv)), 0.0);
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
vec3 EvalSecondaryLight(float seed,vec2 uv,vec3 normal,vec3 ori){
  //因为所有间接光源都是diffuse的，没有方向性，所以积分的时候不用乘cos
  //正常来说直接光照的结果应该可以直接从GBuffer查询，但是由于我们把直接光照放到了这个pass，所以没法查只能当场计算
  vec3 base1,base2;
  LocalBasis(normal,base1,base2);
  mat3 localToWorld = mat3(base1,base2,normal);
  vec3 result = vec3(0.0,0.0,0.0);
  for(int i=0;i<SAMPLE_NUM;i++){
    float pdf;
    //BSDF会随入射角增大而减小，所以采样的时候在法线附近多采一点
    vec3 sampleDirection = localToWorld * SampleHemisphereCos(seed,pdf);
    vec3 hitPos;
    if(RayMarch(ori,sampleDirection,hitPos)){
      result += GetGBufferDirectLight(GetScreenCoordinate(hitPos)) / pdf * EvalDiffuse(sampleDirection,uv);
    }
  }
  return result / float(SAMPLE_NUM);
}
//仅用于测试RayMarch，不保证符合物理
vec3 EvalSpecularRefectionLight(vec2 uv) {
  vec3 ori = GetGBufferPosWorld(uv);
  vec3 wi = normalize(uCameraPos - ori);
  vec3 normal = GetGBufferNormalWorld(uv);
  float dotProduct = dot(wi, normal);
  vec3 L;
  if(dotProduct > 0.1) {
    vec3 wo = 2.0 * dotProduct * normal - wi;
    vec3 hitpos;
    if(RayMarch(ori, wo, hitpos)) {
      L = GetGBufferDirectLight(GetScreenCoordinate(hitpos)); //反射的内容
    } else {
      L = vec3(0.0, 0.0, 0.0);
    }
  } else {
    L = vec3(0.0, 0.0, 0.0);
  }
  return L;
}



void main() {
  float seed = InitRand(gl_FragCoord.xy);
  vec2 screenCoord = GetScreenCoordinate(vPosWorld.xyz);
  vec3 normal = GetGBufferNormalWorld(screenCoord);
  vec3 wi = normalize(uCameraPos - GetGBufferPosWorld(screenCoord));
  vec3 L;

  if(dot(wi,normal)>0.0){
    vec3 directLight = GetGBufferDirectLight(screenCoord);
    if(directLight==vec3(.0,.0,.0)){
      vec3 secondaryLight = EvalSecondaryLight(seed,screenCoord,normal,vPosWorld.xyz);
      L = directLight + secondaryLight;
    }else{
      L = directLight;
    }
  }else{
    L= vec3(0.0,0.0,0.0);
  }

  //L = EvalSpecularRefectionLight(screenCoord);
  //L = GetGBufferDirectLight(screenCoord);
  vec3 color = pow(clamp(L, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2));
  //vec3 temp = vec3((GetScreenCoordinate3D(vPosWorld.xyz).z));
  //vec3 temp = vec3(GetDepth(vPosWorld.xyz));
  gl_FragColor = vec4(color, 1.0);
}
