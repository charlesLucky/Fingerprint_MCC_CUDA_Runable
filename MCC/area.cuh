#ifndef __AREA_CUH__
#define __AREA_CUH__

#include <vector>
#include "cuda.h"

#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include "minutia.cuh"

__host__
std::vector<char> buildValidArea(
  const std::vector<Minutia>& minutiae,
  const int width, const int height);

__host__
void devBuildValidArea(
  const std::vector<Minutia> &minutiae,
  const int width, const int height,
  char *devArea);

#endif
