#ifdef GL_ES
precision mediump float;
#endif

varying highp vec3 vColor;

void main() {
  vec3 color = pow(clamp(vColor, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2));
  gl_FragColor = vec4(color, 1.0);
}