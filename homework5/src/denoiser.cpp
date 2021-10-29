#include "denoiser.h"
#include <iostream>
#include <math.h>

Denoiser::Denoiser() : m_hasPrevFrame(false) {}

void Denoiser::Reprojection(const FrameInfo &frameInfo) {
    int height = m_accColor.m_height;
    int width = m_accColor.m_width;
    Matrix4x4 preVP = m_preFrameInfo.m_matrix[m_preFrameInfo.m_matrix.size() - 1];
#pragma omp parallel for
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            // TODO: Reproject
            int objectId = frameInfo.m_id(x, y);
            Matrix4x4 M_Inverse = Inverse(frameInfo.m_matrix[objectId]);
            Matrix4x4 preM = m_preFrameInfo.m_matrix[objectId];
            Float3 worldPos = frameInfo.m_position(x, y);
            Float3 preScreenCoord = preVP(
                preM(M_Inverse(worldPos, Float3::Point), Float3::Point), Float3::Point);
            if (preScreenCoord.x >= 0 && preScreenCoord.x < width &&
                preScreenCoord.y >= 0 && preScreenCoord.y < height &&
                objectId == m_preFrameInfo.m_id(preScreenCoord.x, preScreenCoord.y)) {
                m_valid(x, y) = true;
                m_misc(x, y) = m_accColor(preScreenCoord.x, preScreenCoord.y);
            } else {
                m_valid(x, y) = false;
            }
        }
    }
    // m_misc存临时结果，m_accColor存上一帧降噪后信息，最后结果要保存到m_accColor
    std::swap(m_misc, m_accColor);
}

void Denoiser::TemporalAccumulation(const Buffer2D<Float3> &curColor) {
    int height = m_accColor.m_height;
    int width = m_accColor.m_width;
    int m_spatialFilterRadius = 3;
#pragma omp parallel for
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            // TODO: Temporal clamp
            Float3 preColor = m_accColor(x, y);
            // TODO: Exponential moving average
            if (m_valid(x, y)) {
                m_misc(x, y) = Lerp(preColor, curColor(x, y), m_alpha);
            } else {
                m_misc(x, y) = curColor(x, y);
            }
        }
    }
    std::swap(m_misc, m_accColor);
}
//单帧降噪
Buffer2D<Float3> Denoiser::Filter(const FrameInfo &frameInfo,
                                  const Buffer2D<Float3> color) {
    int height = frameInfo.m_beauty.m_height;
    int width = frameInfo.m_beauty.m_width;
    Buffer2D<Float3> filteredImage = CreateBuffer2D<Float3>(width, height);
    static const float kCoord = -0.5 / pow(m_sigmaCoord, 2.0);
    static const float kColor = -0.5 / pow(m_sigmaColor, 2.0);
    static const float kNormal = -0.5 / pow(m_sigmaNormal, 2.0);
    static const float kPlane = -0.5 / pow(m_sigmaPlane, 2.0);
#pragma omp parallel for
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            // TODO: Joint bilateral filter
            float weightSum = 0.0;
            for (int i = std::max(0, x - m_spatialFilterRadius);
                 i < std::min(width, x + m_spatialFilterRadius + 1); i++) {
                for (int j = std::max(0, y - m_spatialFilterRadius);
                     j < std::min(height, y + m_spatialFilterRadius + 1); j++) {
                    float dCoord;
                    float dColor;
                    float dNormal;
                    float dPlane;
                    //没有物体的地方法线为(0,0,0)
                    if (x == i && y == j) {
                        dCoord = 0.0;
                        dColor = 0.0;
                        dNormal = 0.0;
                        dPlane = 0.0;
                    } else {
                        dCoord = SqrDistance(frameInfo.m_position(i, j),
                                             frameInfo.m_position(x, y));
                        dColor = SqrDistance(frameInfo.m_beauty(i, j),
                                             frameInfo.m_beauty(x, y));
                        dNormal =
                            std::pow(std::acos(std::min(Dot(frameInfo.m_normal(i, j),
                                                            frameInfo.m_normal(x, y)),
                                                        1.0f)),
                                     2.0);
                        dPlane = std::pow(
                            Dot(frameInfo.m_normal(x, y),
                                frameInfo.m_position(i, j) - frameInfo.m_position(x, y)),
                            2.0);
                    }
                    float weight = exp(kCoord * dCoord + kColor * dColor +
                                       kNormal * dNormal + kPlane * dPlane);
                    // if (true) {
                    //     std::cout << dCoord << ' ' << dColor << ' ' << dNormal << " "
                    //               << dPlane << '\n';
                    // }

                    filteredImage(x, y) += color(i, j) * weight;
                    weightSum += weight;
                }
            }
            filteredImage(x, y) /= weightSum;
        }
    }
    return filteredImage;
}

void Denoiser::InitAccColor(const FrameInfo &frameInfo,
                            const Buffer2D<Float3> &filteredColor) {
    m_accColor.Copy(filteredColor);
    int height = m_accColor.m_height;
    int width = m_accColor.m_width;
    m_misc = CreateBuffer2D<Float3>(width, height);
    m_valid = CreateBuffer2D<bool>(width, height);
}

void Denoiser::store(const FrameInfo &frameInfo) { m_preFrameInfo = frameInfo; }

Buffer2D<Float3> Denoiser::ProcessFrame(const FrameInfo &frameInfo) {
    // Filter current frame
    if (SpatialFirst) {
        Buffer2D<Float3> filteredColor;
        if (useSpatial) {
            filteredColor = Filter(frameInfo, frameInfo.m_beauty);
        } else {
            filteredColor = frameInfo.m_beauty;
        }

        // Reproject previous frame color to current
        if (m_hasPrevFrame && useTemporal) {
            Reprojection(frameInfo);
            TemporalAccumulation(filteredColor);
        } else {
            InitAccColor(frameInfo, filteredColor);
        }
        // 把当前帧信息存起来
        store(frameInfo);
        //第一帧之后就使用Temporal
        if (!m_hasPrevFrame) {
            m_hasPrevFrame = true;
        }
        return m_accColor;
    } else {
        // Reproject previous frame color to current
        if (useTemporal && m_hasPrevFrame) {
            Reprojection(frameInfo);
            TemporalAccumulation(frameInfo.m_beauty);
        } else {
            InitAccColor(frameInfo, frameInfo.m_beauty);
        }
        // 把当前帧信息存起来
        store(frameInfo);
        //第一帧之后就使用Temporal
        if (!m_hasPrevFrame) {
            m_hasPrevFrame = true;
        }
        Buffer2D<Float3> filteredColor;
        if (useSpatial) {
            filteredColor = Filter(frameInfo, m_accColor);
        } else {
            filteredColor = m_accColor;
        }
        return filteredColor;
    }
}
