#include <vector>
#include <iostream>
#include <algorithm>

#include <dirent.h>

#include "errors.h"
#include "debug.h"
#include "constants.cuh"
#include "template.cuh"
#include "matcher.cuh"
#include "io.cuh"
#include "mcc.cuh"
#include "consolidation.cuh"
#include <string>  

using namespace std;

bool buildTemplateFromFile(
    const char *input,
    const char *output) {
  int width, height, dpi, n;
  vector<Minutia> minutiae;
  if (!loadMinutiaeFromFile(input, width, height, dpi, n, minutiae))
    return false;

  vector<char> cylinderValidities, cellValidities, cellValues;
  buildTemplate(minutiae, width, height,
    cylinderValidities, cellValidities, cellValues);
  handleError(cudaDeviceSynchronize());

  return saveTemplateToFile(
    output, width, height, dpi, n, minutiae,
    cylinderValidities.size(), cylinderValidities, cellValidities, cellValues);
}

bool buildSimilarityFromTemplate(
    const char *template1,
    const char *template2,
    const char *output) {
  int width1, height1, dpi1, n1;
  vector<Minutia> minutiae1;
  int m1;
  vector<char> cylinderValidities1, cellValidities1, cellValues1;
  if (!loadTemplateFromFile(template1,
      width1, height1, dpi1, n1, minutiae1,
      m1, cylinderValidities1, cellValidities1, cellValues1))
    return false;

  int width2, height2, dpi2, n2;
  vector<Minutia> minutiae2;
  int m2;
  vector<char> cylinderValidities2, cellValidities2, cellValues2;
  if (!loadTemplateFromFile(template2,
      width2, height2, dpi2, n2, minutiae2,
      m2, cylinderValidities2, cellValidities2, cellValues2))
    return false;

  vector<float> matrix;
  matchTemplate(
    minutiae1, cylinderValidities1, cellValidities1, cellValues1,
    minutiae2, cylinderValidities2, cellValidities2, cellValues2,
    matrix);
  auto similarity = LSSR(matrix, m1, m2, minutiae1, minutiae2);
  printf("Similarity: %f\n", similarity);
  return saveSimilarityToFile(output, m1, m2, matrix);
}


float buildSimilarityFromTemplateV2(
	const char *template1,
	const char *template2) {
	int width1, height1, dpi1, n1;
	vector<Minutia> minutiae1;
	int m1;
	vector<char> cylinderValidities1, cellValidities1, cellValues1;
	if (!loadTemplateFromFile(template1,
		width1, height1, dpi1, n1, minutiae1,
		m1, cylinderValidities1, cellValidities1, cellValues1))
		return false;

	int width2, height2, dpi2, n2;
	vector<Minutia> minutiae2;
	int m2;
	vector<char> cylinderValidities2, cellValidities2, cellValues2;
	if (!loadTemplateFromFile(template2,
		width2, height2, dpi2, n2, minutiae2,
		m2, cylinderValidities2, cellValidities2, cellValues2))
		return false;

	vector<float> matrix;
	matchTemplate(
		minutiae1, cylinderValidities1, cellValidities1, cellValues1,
		minutiae2, cylinderValidities2, cellValidities2, cellValues2,
		matrix);
	auto similarity = LSSR(matrix, m1, m2, minutiae1, minutiae2);
	printf("Similarity: %f\n", similarity);
	return similarity;
}

bool buildSimilarityFromMinutiae(
    const char *minutiae1,
    const char *minutiae2,
    const char *output) {
  MCC mcc(minutiae1);
  if (!mcc.load() || !mcc.build()) return false;

  float similarity;
  int n, m;
  vector<float> matrix;
  bool ret = mcc.match(minutiae2, similarity, n, m, matrix);
  if (!ret) return false;
  printf("Similarity: %f\n", similarity);
  return saveSimilarityToFile(output, n, m, matrix);
}

bool matchMany(const char *input, const char *targetDir) {
  DIR *dir;
  struct dirent *ent;
  vector<string> targets;
  vector<float> values;
  string stargetDir(targetDir);
  if (stargetDir.back() != '/')
    stargetDir += '/';

  if ((dir = opendir(targetDir)) != NULL) {
    while ((ent = readdir(dir)) != NULL) {
      if (ent->d_type != DT_REG)
        continue;
      targets.push_back(stargetDir + string(ent->d_name));
    }
    closedir(dir);
    values.resize(targets.size());
    MCC mcc(input, false);
    mcc.matchMany(targets, values);
    return true;
  }
  return false;
}

void printUsage(char const *argv[]) {
  cerr << "usage: " << argv[0] << " [mcc|template|match] [options]\n";
  cerr << endl;
  cerr << "mcc\t\t: <in:minutia1> <in:minutia2> <out:similarity>\n";
  cerr << "template\t: <in:minutia> <out:template>\n";
  cerr << "match\t\t: <in:template1> <in:template2> <out:similarity>\n";
  cerr << "many\t\t: <in:minutia> <in:dir>\n";
}


void comb(int N, int K)
{
	std::string bitmask(K, 1); // K leading 1's
	bitmask.resize(N, 0); // N-K trailing 0's
						  // print integers and permute bitmask
	do {
		for (int i = 0; i < N; ++i) // [0..N-1] integers
		{
			if (bitmask[i]) std::cout << " " << i;
		}
		std::cout << std::endl;
	} while (std::prev_permutation(bitmask.begin(), bitmask.end()));
}

int main(int argc, char const *argv[]) {
	/*
 if (argc > 1) {
    if (strncmp(argv[1], "mcc", 3) == 0 && argc == 5) {
      return !buildSimilarityFromMinutiae(argv[2], argv[3], argv[4]);
    } else if (strncmp(argv[1], "template", 8) == 0 && argc == 4) {
      return !buildTemplateFromFile(argv[2], argv[3]);
    } else if (strncmp(argv[1], "match", 5) == 0 && argc == 5) {
      return !buildSimilarityFromTemplate(argv[2], argv[3], argv[4]);
    } else if (strncmp(argv[1], "many", 4) == 0 && argc == 4) {
      return !matchMany(argv[2], argv[3]);
    }
  }
  printUsage(argv);
  */
	 
  /*
	string pointsdir = "C:/project source file/SampleMinutiae";
	string outdir = "C:/project source file/SampleMinutiae_OUT";
	for (int i = 1; i <= 10; i++) {
		for (int j = 1; j <= 12; j++) {
			string a = pointsdir + "/" + to_string(i) + "_" + to_string(j) + ".txt";
			string b = outdir + "/" + to_string(i) + "_" + to_string(j) + ".txt";
			buildTemplateFromFile(a.c_str(), b.c_str());
		}
	} 
	*/

	string pointsdir = "C:/project source file/SampleMinutiae";
	string outdir = "C:/project source file/SampleMinutiae_OUT";
	float gen[70];
	int count = 0;
	for (int i = 1; i <= 10; i++) {
		for (int j = 2; j <= 8; j++) {
			string a = outdir + "/" + to_string(i) + "_" + to_string(1) + ".txt";
			string b = outdir + "/" + to_string(i) + "_" + to_string(j) + ".txt";

			float simi = buildSimilarityFromTemplateV2(a.c_str(), b.c_str());
		}
	}
	std::cout << "**********************" << std::endl;


for (int i = 1; i < 10; i++) {
		
	for (int j = i+1; j <= 10; j++) {
		string a = outdir + "/" + to_string(i) + "_" + to_string(1) + ".txt";
		string b = outdir + "/" + to_string(j) + "_" + to_string(1) + ".txt";
		float simi = buildSimilarityFromTemplateV2(a.c_str(), b.c_str());
		 
	}
} ;

	return 1;

}
