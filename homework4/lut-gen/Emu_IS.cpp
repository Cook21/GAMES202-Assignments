#include "vec.h"
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <random>
#include <sstream>
#include <vector>

#define STB_IMAGE_WRITE_IMPLEMENTATION

#include "stb_image_write.h"

const int resolution = 128;

Vec2f Hammersley(uint32_t i, uint32_t N)
{ // 0-1的2D随机采样
    uint32_t bits = (i << 16u) | (i >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    float rdi = float(bits) * 2.3283064365386963e-10;
    return { float(i) / float(N), rdi };
}
float fersnelSchlick(float roughness, float NdotWi)
{
    return roughness + (1.0 - roughness) * pow((1.0 - NdotWi), 5.0);
}

float DistributionGGX(Vec3f N, Vec3f H, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = std::max(dot(N, H), 0.0f);
    float NdotH2 = NdotH * NdotH;

    float nom = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / std::max(denom, 0.0001f);
}
Vec3f ImportanceSampleGGX(Vec2f Xi, Vec3f N, float roughness)
{
    float a = roughness * roughness;

    //TODO: in spherical space - Bonus 1
    float theta = atan(a * sqrt(Xi.x) / sqrt(1 - Xi.x));
    float phi = 2.0f * PI * Xi.y;

    //TODO: from spherical space to cartesian space - Bonus 1
    //如果N!=[0,0,1]还要对H做旋转，这里就省略了
    Vec3f H = Vec3f(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));

    //TODO: tangent coordinates - Bonus 1

    //TODO: transform H to tangent space - Bonus 1

    return H;
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    // TODO: To calculate Schlick G1 here - Bonus 1
    float k = (roughness * roughness) / 2.0f;
    //float k = pow((roughness + 1.0f), 2.0f) / 8.0f;

    float nom = NdotV;
    float denom = NdotV * (1.0f - k) + k;

    return nom / denom;
    return 1.0f;
}

float GeometrySmith(float roughness, float NoV, float NoL)
{
    float ggx2 = GeometrySchlickGGX(NoV, roughness);
    float ggx1 = GeometrySchlickGGX(NoL, roughness);

    return ggx1 * ggx2;
}

Vec3f IntegrateBRDF(Vec3f wo, float roughness)
{

    const int sample_count = 1024;
    float R = 0.0;
    Vec3f N = Vec3f(0.0, 0.0, 1.0);
    for (int i = 0; i < sample_count; i++) {
        Vec2f Xi = Hammersley(i, sample_count);
        Vec3f H = ImportanceSampleGGX(Xi, N, roughness);
        Vec3f wi = normalize(H * 2.0f * dot(wo, H) - wo);
        float NoWi = std::max(wi.z, 0.0f);
        float NoWo = std::max(dot(N, wo), 0.0f);
        float NoH = std::max(H.z, 0.0f);
        float HoWo = std::max(dot(wo, H), 0.0f);
        float HoWi = std::max(dot(wi,H),0.0f);
        

        // TODO: To calculate (fr * ni) / p_o here - Bonus 1
        //float FersnelTerm = fersnelSchlick(roughness, dot(wi, N));
        float GeometryTerm = GeometrySmith(roughness, NoWi, NoWo);
        //float NormalDistributionTerm = DistributionGGX(N, H, roughness);
        //乘以cos项后dot(wi, N)约掉了
        R += HoWo * GeometryTerm  / NoWo / NoH;
        // Split Sum - Bonus 2
    }

    return Vec3f(R / sample_count);
}

int main()
{
    uint8_t data[resolution * resolution * 3];
    float step = 1.0 / resolution;
    for (int i = 0; i < resolution; i++) {
        for (int j = 0; j < resolution; j++) {
            float roughness = step * (static_cast<float>(i) + 0.5f);
            float NdotV = step * (static_cast<float>(j) + 0.5f);
            Vec3f V = Vec3f(std::sqrt(1.f - NdotV * NdotV), 0.f, NdotV);

            Vec3f irr = IntegrateBRDF(V, roughness);

            data[(i * resolution + j) * 3 + 0] = uint8_t(irr.x * 255.0);
            data[(i * resolution + j) * 3 + 1] = uint8_t(irr.y * 255.0);
            data[(i * resolution + j) * 3 + 2] = uint8_t(irr.z * 255.0);
        }
    }
    stbi_flip_vertically_on_write(true);
    stbi_write_png("GGX_E_LUT.png", resolution, resolution, 3, data, resolution * 3);

    std::cout << "Finished precomputed!" << std::endl;
    return 0;
}