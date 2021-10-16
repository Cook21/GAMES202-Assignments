//环境光项，包含RGB三通道，与顶点无关所以是uniform变量
uniform mat3 uPrecomputeL[3];
//传输项，与顶点有关
attribute mat3 aPrecomputeLT;
attribute vec3 aVertexPosition;

uniform mat4 uModelMatrix;
uniform mat4 uViewMatrix;
uniform mat4 uProjectionMatrix;
varying highp vec3 vColor;
const float pi = 3.1415926;
const float albedo = 1.0;
void main(){
    gl_Position = uProjectionMatrix * uViewMatrix * uModelMatrix * vec4(aVertexPosition, 1.0);
    vColor = vec3(0.0);
    for(int channel = 0;channel<3;channel++){
        for(int i = 0; i < 3;i++){
            vColor[channel] += albedo / pi * dot(uPrecomputeL[channel][i],aPrecomputeLT[i]);
        }
    }
    return;
}