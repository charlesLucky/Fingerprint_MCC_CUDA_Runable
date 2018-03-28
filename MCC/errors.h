
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include <cstdio>


#define handleError(err) (_handleError(err, __FILE__, __LINE__))
inline void _handleError(cudaError_t _a,const char *file,int line) {
	if (_a != cudaSuccess) {
		printf("error");
	}
}