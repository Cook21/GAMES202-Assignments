class PRTMaterial extends Material {

    constructor(vertexShader, fragmentShader) {

        super({ 'uSampler': { type: 'texture', value: color }, },
            ['aPrecomputeLT'], vertexShader, fragmentShader, null);
    }
}

async function buildPRTMaterial(color, specular, light, translate, scale, vertexPath, fragmentPath) {


    let vertexShader = await getShaderString(vertexPath);
    let fragmentShader = await getShaderString(fragmentPath);

    return new PRTMaterial(vertexShader, fragmentShader);

}