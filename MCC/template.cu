#include <vector>

#include "minutia.cuh"
#include "area.cuh"
#include "constants.cuh"
#include "util.cuh"
#include "errors.h"
#include "debug.h"

#include "cuda_runtime.h"
#include "device_launch_parameters.h"

using namespace std;

bool initialized = false;
int numCellsInCylinder = 0;

__host__ void initialize() {
  if (initialized) return;
  initialized = true;

  numCellsInCylinder = 0;
  float temp = DELTA_S/2;
  for (int i = 0; i < NS; ++i) {
    float x = DELTA_S * i + temp;
    float dx = x-R;
    for (int j = 0; j < NS; ++j) {
      float y = DELTA_S * j + temp;
      float dy = y-R;
      if (dx*dx + dy*dy <= R_SQR) ++numCellsInCylinder;
    }
  }
}

__host__ __device__ __inline__
float spatialContribution(
    int mt_x, int mt_y, int pi, int pj) {
  auto gaussian = [&](int t_sqr) -> float {
    return I_2_SIGMA_S_SQRT_PI * expf(-t_sqr * I_2_SIGMA_S_SQR);
  };
  return gaussian(sqrDistance(mt_x, mt_y, pi, pj));
}

__host__ __device__ __inline__
float directionalContribution(
    float m_theta, float mt_theta, float dphik) {
  // http://www.wolframalpha.com/input/?i=integrate+(e%5E(-(t%5E2)%2F(2(x%5E2)))+dt)
  auto integrate = [&](float val) -> float {
    return SQRT_PI_2_SIGMA_D * erff(val * I_SQRT_2_SIGMA_D);
  };
  auto gaussian = [&](float val) -> float {
    return I_SQRT_2_PI_SIGMA_D *
      (integrate(val+DELTA_D_2)-integrate(val-DELTA_D_2));
  };
  return gaussian(
    angle(dphik, angle(m_theta, mt_theta)));
}

__global__
void buildCylinder(
    Minutia *minutiae,
    int width, int height,
    char *validArea,
    int numCellsInCylinder,
    char *cylinderValidities,
    char *cellValidities,
    char *cellValues) {
  extern __shared__ int shared[];

  const int N = gridDim.x;
  Minutia *sharedMinutiae = (Minutia*)shared;

  int idxMinutia = blockIdx.x;
  int idxThread = threadIdx.y * blockDim.x + threadIdx.x;
  int contributed = 0;

  if (idxThread < N) {
    sharedMinutiae[idxThread] = minutiae[idxThread];
    if (idxThread != idxMinutia) {
      auto dist = sqrDistance(
        sharedMinutiae[idxThread].x, sharedMinutiae[idxThread].y,
        minutiae[idxMinutia].x, minutiae[idxMinutia].y);
      contributed = dist <= (R+SIGMA_3S)*(R+SIGMA_3S);
    }
  }
  int sumContributed = __syncthreads_count(contributed);

  Minutia m = sharedMinutiae[idxMinutia];

  float halfNS = (NS + 1) / 2.0f;
  float halfNSi = (threadIdx.x+1) - halfNS;
  float halfNSj = (threadIdx.y+1) - halfNS;
  float sint, cost;
  sincosf(m.theta, &sint, &cost);
  int pi = m.x + roundf(DELTA_S * (cost * halfNSi + sint * halfNSj));
  int pj = m.y + roundf(DELTA_S * (-sint * halfNSi + cost * halfNSj));

  char validity = pi >= 0 && pi < width && pj >= 0 && pj < height
    && validArea[pj * width + pi]
    && sqrDistance(m.x, m.y, pi, pj) <= R_SQR;

  int idx = idxMinutia * NC + threadIdx.y * NS * ND + threadIdx.x * ND;
  for (int k = 0; k < ND; ++k) {
    char value = 0;

    if (validity) {
      float dphik = -M_PI + (k + 0.5f) * DELTA_D;
      float sum = 0.0f;

      for (int l = 0; l < N; ++l) {
        if (l == idxMinutia)
          continue;

        Minutia mt(sharedMinutiae[l]);
        if (sqrDistance(mt.x, mt.y, pi, pj) > SIGMA_9S_SQR)
          continue;

        float sContrib = spatialContribution(mt.x, mt.y, pi, pj);
        float dContrib = directionalContribution(m.theta, mt.theta, dphik);
        sum += sContrib * dContrib;
      }

      if (sum >= MU_PSI)
        value = 1;
    }
    cellValidities[idx+k] = validity;
    cellValues[idx+k] = value;
  }

  int sumValidities = __syncthreads_count(validity);
  if (threadIdx.x == 0 && threadIdx.y == 0) {
    cylinderValidities[idxMinutia] = sumContributed >= MIN_M &&
      (float)sumValidities/(numCellsInCylinder) >= MIN_VC;
    devDebug("Minutia %2d VC: ((%3d/%d) = %.5f) >= %.2f, M: %2d >= %d\n",
      idxMinutia,
      sumValidities, numCellsInCylinder,
      (float)sumValidities/(numCellsInCylinder), MIN_VC,
      sumContributed, MIN_M);
  }
}

__host__
void devBuildTemplate(
    Minutia *devMinutiae, const int n,
    char *devArea, const int width, const int height,
    char *devCylinderValidities,
    char *devCellValidities,
    char *devCellValues) {

  initialize();

  dim3 blockDim(NS, NS);
  int sharedSize = n * sizeof(Minutia);
  buildCylinder<<<n, blockDim, sharedSize>>>(
    devMinutiae, width, height, devArea, numCellsInCylinder,
    devCylinderValidities, devCellValidities, devCellValues);
}

__host__
void buildTemplate(
    const vector<Minutia>& minutiae,
    const int width, const int height,
    vector<char>& cylinderValidities,
    vector<char>& cellValidities,
    vector<char>& cellValues) {

  auto area = buildValidArea(minutiae, width, height);

  Minutia *devMinutiae;
  char *devArea;
  char *devCylinderValidities, *devCellValidities, *devCellValues;
  size_t devMinutiaeSize = minutiae.size() * sizeof(Minutia);
  size_t devAreaSize = width * height * sizeof(char);
  size_t devCylinderValiditiesSize = minutiae.size() * sizeof(char);
  size_t devCellValiditiesSize = minutiae.size() * NC * sizeof(char);
  size_t devCellValuesSize = minutiae.size() * NC * sizeof(char);
  handleError(
    cudaMalloc(&devMinutiae, devMinutiaeSize));
  handleError(
    cudaMemcpy(devMinutiae, minutiae.data(), devMinutiaeSize, cudaMemcpyHostToDevice));
  handleError(
    cudaMalloc(&devArea, devAreaSize));
  handleError(
    cudaMemcpy(devArea, area.data(), devAreaSize, cudaMemcpyHostToDevice));
  handleError(
    cudaMalloc(&devCylinderValidities, devCylinderValiditiesSize));
  handleError(
    cudaMalloc(&devCellValues, devCellValuesSize));
  handleError(
    cudaMalloc(&devCellValidities, devCellValiditiesSize));

  devBuildTemplate(
    devMinutiae, minutiae.size(),
    devArea, width, height,
    devCylinderValidities,
    devCellValidities,
    devCellValues);

  cylinderValidities.resize(minutiae.size());
  cellValidities.resize(minutiae.size() * NC);
  cellValues.resize(minutiae.size() * NC);
  handleError(
    cudaMemcpy(cylinderValidities.data(), devCylinderValidities, devCylinderValiditiesSize, cudaMemcpyDeviceToHost));
  handleError(
    cudaMemcpy(cellValidities.data(), devCellValidities, devCellValiditiesSize, cudaMemcpyDeviceToHost));
  handleError(
    cudaMemcpy(cellValues.data(), devCellValues, devCellValuesSize, cudaMemcpyDeviceToHost));

  cudaFree(devMinutiae);
  cudaFree(devArea);
  cudaFree(devCylinderValidities);
  cudaFree(devCellValidities);
  cudaFree(devCellValues);
}
