#ifdef GL_ES
precision mediump float;
#endif

// Phong related variables
uniform sampler2D uSampler;
uniform vec3 uKd;
uniform vec3 uKs;
uniform vec3 uLightPos;
uniform vec3 uCameraPos;
uniform vec3 uLightIntensity;

varying highp vec2 vTextureCoord;
varying highp vec3 vFragPos;
varying highp vec3 vNormal;

// Shadow map related variables
#define NUM_SAMPLES 20
#define BLOCKER_SEARCH_NUM_SAMPLES NUM_SAMPLES
#define PCF_NUM_SAMPLES NUM_SAMPLES
#define NUM_RINGS 10

#define EPS 1e-3
#define PI 3.141592653589793
#define PI2 6.283185307179586

uniform sampler2D uShadowMap;

varying vec4 vPositionFromLight;

highp float rand_1to1(highp float x ) { 
  // -1 -1
  return fract(sin(x)*10000.0);
}

highp float rand_2to1(vec2 uv ) { 
  // 0 - 1
	const highp float a = 12.9898, b = 78.233, c = 43758.5453;
	highp float dt = dot( uv.xy, vec2( a,b ) ), sn = mod( dt, PI );
	return fract(sin(sn) * c);
}

float unpack(vec4 rgbaDepth) {
    const vec4 bitShift = vec4(1.0, 1.0/256.0, 1.0/(256.0*256.0), 1.0/(256.0*256.0*256.0));
    return dot(rgbaDepth, bitShift);
}

vec2 poissonDisk[NUM_SAMPLES];

void poissonDiskSamples( const in vec2 randomSeed ) {

  float ANGLE_STEP = PI2 * float( NUM_RINGS ) / float( NUM_SAMPLES );
  float INV_NUM_SAMPLES = 1.0 / float( NUM_SAMPLES );

  float angle = rand_2to1( randomSeed ) * PI2;
  float radius = INV_NUM_SAMPLES;
  float radiusStep = radius;

  for( int i = 0; i < NUM_SAMPLES; i ++ ) {
    poissonDisk[i] = vec2( cos( angle ), sin( angle ) ) * pow( radius, 0.75 );
    radius += radiusStep;
    angle += ANGLE_STEP;
  }
}

void uniformDiskSamples( const in vec2 randomSeed ) {

  float randNum = rand_2to1(randomSeed);
  float sampleX = rand_1to1( randNum ) ;
  float sampleY = rand_1to1( sampleX ) ;

  float angle = sampleX * PI2;
  float radius = sqrt(sampleY);

  for( int i = 0; i < NUM_SAMPLES; i ++ ) {
    poissonDisk[i] = vec2( radius * cos(angle) , radius * sin(angle)  );

    sampleX = rand_1to1( sampleY ) ;
    sampleY = rand_1to1( sampleX ) ;

    angle = sampleX * PI2;
    radius = sqrt(sampleY);
  }
}

float findBlocker2( sampler2D shadowMap,  vec2 uv, float zReceiver ) {
  poissonDiskSamples(uv);
  //uniformDiskSamples(uv);

  float textureSize = 400.0;

  // 注意 block 的步长要比 PCSS 中的 PCF 步长长一些，这样生成的软阴影会更加柔和
  float filterStride = 6.0;
  float filterRange = 1.0 / textureSize * filterStride;

  // 有多少点在阴影里
  int shadowCount = 0;
  float blockDepth = 0.0;
  for( int i = 0; i < NUM_SAMPLES; i ++ ) {
    vec2 sampleCoord = poissonDisk[i] * filterRange + uv;
    vec4 closestDepthVec = texture2D(shadowMap, sampleCoord); 
    float closestDepth = unpack(closestDepthVec);
    if(zReceiver > closestDepth + 0.01){
      blockDepth += closestDepth;
      shadowCount += 1;
    }
  }

  if(shadowCount==NUM_SAMPLES){
    return 2.0;
  }else if(shadowCount == 0){
    return -1.0;
  }
  // 平均
  return blockDepth / float(shadowCount);
}


float findBlocker( sampler2D shadowMap,  vec2 uv, float zReceiver ) {
  float filterRadius = 3.0;
  float textureSize = 200.0;
  float filterSize = filterRadius/textureSize;
  float bias = -0.01;
  poissonDiskSamples(uv);
  //uniformDiskSamples(uv);
  float depthSum = 0.0;
  int occlusionCount = 0;
  for( int i = 0; i < NUM_SAMPLES; i ++ ){
    vec4 texel = texture2D(shadowMap, uv + poissonDisk[i] * filterSize);
    float occlusionDepth = unpack(texel);
    if( zReceiver + bias > occlusionDepth){
      depthSum += occlusionDepth;
      occlusionCount++;
    }
  }
  if(occlusionCount==0){
    return -1.0;
  }else if(occlusionCount==NUM_SAMPLES){
    return 2.0;
  }else{
    return depthSum / float(occlusionCount);
  }
}



float PCF(sampler2D shadowMap, vec4 coords, float filterSize) {
  float bias = 0.0001;
  //poissonDiskSamples(coords.xy);
  //uniformDiskSamples(coords.xy);
  int sum = 0;
  for( int i = 0; i < NUM_SAMPLES; i ++ ){
    vec4 texel = texture2D(shadowMap, coords.xy + poissonDisk[i] * filterSize);
    float occlusionDepth = unpack(texel);
    if(coords.z - bias < occlusionDepth){
      sum++;
    }
  }
  return float(sum) / float(NUM_SAMPLES);
  
}

float PCSS(sampler2D shadowMap, vec4 coords){

  // STEP 1: avgblocker depth
  float blockerAvgDepth = findBlocker(shadowMap,coords.xy,coords.z);
  float textureSize = 200.0;
  if(blockerAvgDepth<0.0){
    return 1.0;
  }else if(blockerAvgDepth>1.0){
    return 0.0;
  } else {
    
    float lightWidth = 5.0;
    // STEP 2: penumbra size
    float penumbraWidth = lightWidth * (coords.z - blockerAvgDepth) / blockerAvgDepth;
    // STEP 3: filtering
    return PCF(shadowMap,coords,penumbraWidth / textureSize);
  }
}





float useShadowMap(sampler2D shadowMap, vec4 shadowCoord){
  vec4 texel = texture2D(shadowMap,shadowCoord.xy);
  float occlusionDepth = unpack(texel);
  if(shadowCoord.z < occlusionDepth){
    return 1.0;
  }else{
    return 0.0;
  }
  
}

vec3 blinnPhong() {
  vec3 color = texture2D(uSampler, vTextureCoord).rgb;
  color = pow(color, vec3(2.2));

  vec3 ambient = 0.05 * color;

  vec3 lightDir = normalize(uLightPos);
  vec3 normal = normalize(vNormal);
  float diff = max(dot(lightDir, normal), 0.0);
  vec3 light_atten_coff =
      uLightIntensity / pow(length(uLightPos - vFragPos), 2.0);
  vec3 diffuse = diff * light_atten_coff * color;

  vec3 viewDir = normalize(uCameraPos - vFragPos);
  vec3 halfDir = normalize((lightDir + viewDir));
  float spec = pow(max(dot(halfDir, normal), 0.0), 32.0);
  vec3 specular = uKs * light_atten_coff * spec;

  vec3 radiance = (ambient + diffuse + specular);
  vec3 phongColor = pow(radiance, vec3(1.0 / 2.2));
  return phongColor;
}

void main(void) {
  //把齐次坐标化为标准坐标
  vec3 shadowCoord = vPositionFromLight.xyz / vPositionFromLight.w;
  //把坐标从[-1,1]变换到[0,1]
  shadowCoord = shadowCoord * 0.5 + 0.5;
  float visibility;
  //visibility = useShadowMap(uShadowMap, vec4(shadowCoord, 1.0));
  //visibility = PCF(uShadowMap, vec4(shadowCoord, 1.0),0.005);
  visibility = PCSS(uShadowMap, vec4(shadowCoord, 1.0));

  vec3 phongColor = blinnPhong();

  gl_FragColor = vec4(phongColor * visibility, 1.0);
  //gl_FragColor = vec4(phongColor, 1.0);
}