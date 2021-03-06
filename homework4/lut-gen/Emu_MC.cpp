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

typedef struct samplePoints {
    std::vector<Vec3f> directions;
    std::vector<float> PDFs;
} samplePoints;

samplePoints squareToCosineHemisphere(int sample_count)
{
    samplePoints samlpeList;
    const int sample_side = static_cast<int>(floor(sqrt(sample_count)));

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_real_distribution<> rng(0.0, 1.0);
    for (int t = 0; t < sample_side; t++) {
        for (int p = 0; p < sample_side; p++) {
            double samplex = (t + rng(gen)) / sample_side;
            double sampley = (p + rng(gen)) / sample_side;

            double theta = 0.5f * acos(1 - 2 * samplex);
            double phi = 2 * M_PI * sampley;
            Vec3f wi = Vec3f(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
            float pdf = wi.z / PI;

            samlpeList.directions.push_back(wi);
            samlpeList.PDFs.push_back(pdf);
        }
    }
    return samlpeList;
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

float GeometrySchlickGGX(float NdotV, float roughness)
{
    //float k = (roughness * roughness) / 2.0f;
    float k = pow((roughness + 1.0f), 2.0f) / 8.0f;

    float nom = NdotV;
    float denom = NdotV * (1.0f - k) + k;

    return nom / denom;
}

float GeometrySmith(float roughness, float NoV, float NoL)
{
    float ggx2 = GeometrySchlickGGX(NoV, roughness);
    float ggx1 = GeometrySchlickGGX(NoL, roughness);

    return ggx1 * ggx2;
}

Vec3f IntegrateBRDF(Vec3f wo, float roughness, float NdotWo)
{
    float R = 0.0;
    float G = 0.0;
    float B = 0.0;
    const int sample_count = 1024;
    Vec3f N = Vec3f(0.0, 0.0, 1.0);

    samplePoints sampleList = squareToCosineHemisphere(sample_count);
    for (int i = 0; i < sample_count; i++) {
        // TODO: To calculate (fr * ni) / p_o here
        Vec3f wi = sampleList.directions[i];
        //std::cout << length(wi) << '\n';
        Vec3f h = normalize(wi + wo);
        float pdf = sampleList.PDFs[i];
        //float FersnelTerm = fersnelSchlick(roughness, dot(wi, N));
        float FersnelTerm=1.0f;
        float GeometryTerm = GeometrySmith(roughness, dot(wi, N), dot(wo, N));
        float NormalDistributionTerm = DistributionGGX(N, h, roughness);
        //??????cos??????dot(wi, N)?????????
        R += FersnelTerm * GeometryTerm * NormalDistributionTerm / 4.0 / dot(wo, N) / pdf;
    }

    return { R / sample_count, R / sample_count, R / sample_count };
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
            
            Vec3f irr = IntegrateBRDF(V, roughness, NdotV);

            data[(i * resolution + j) * 3 + 0] = uint8_t(irr.x * 255.0);
            data[(i * resolution + j) * 3 + 1] = uint8_t(irr.y * 255.0);
            data[(i * resolution + j) * 3 + 2] = uint8_t(irr.z * 255.0);
        }
    }
    stbi_flip_vertically_on_write(true);
    stbi_write_png("GGX_E_MC_LUT.png", resolution, resolution, 3, data, resolution * 3);

    std::cout << "Finished precomputed!" << std::endl;
    return 0;
}