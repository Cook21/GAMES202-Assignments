#pragma once

#define NOMINMAX
#include <string>
#include <cmath>

#include "filesystem/path.h"

#include "util/image.h"
#include "util/mathutil.h"

struct FrameInfo {
  public:
    Buffer2D<Float3> m_beauty;
    Buffer2D<float> m_depth;
    Buffer2D<Float3> m_normal;
    Buffer2D<Float3> m_position;
    Buffer2D<float> m_id;
    std::vector<Matrix4x4> m_matrix;
};

class Denoiser {
  public:
    Denoiser();

    void InitAccColor(const FrameInfo &frameInfo, const Buffer2D<Float3> &filteredColor);
    void store(const FrameInfo &frameInfo);

    void Reprojection(const FrameInfo &frameInfo);
    void TemporalAccumulation(const Buffer2D<Float3> &curFilteredColor);
    Buffer2D<Float3> Filter(const FrameInfo &frameInfo,const Buffer2D<Float3> color);

    Buffer2D<Float3> ProcessFrame(const FrameInfo &frameInfo);

  public:
    FrameInfo m_preFrameInfo;
    Buffer2D<Float3> m_accColor;
    Buffer2D<Float3> m_misc;
    Buffer2D<bool> m_valid;
    bool m_hasPrevFrame;

    const bool useSpatial = true;
    const bool useTemporal = true;
    const bool SpatialFirst = false;

    float m_alpha = 0.3f;
    float m_sigmaPlane = 0.002f;
    float m_sigmaColor = 0.9f;
    float m_sigmaNormal = 0.1f;
    float m_sigmaCoord = 0.01f;
    int m_spatialFilterRadius = 7;
};