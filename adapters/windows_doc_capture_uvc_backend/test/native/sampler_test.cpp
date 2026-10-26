#include "../../windows/rgba_sampler.h"
#include <cstdlib>
#include <iostream>
#include <vector>
#include <chrono>
#define CHECK(condition) do { if (!(condition)) { std::cerr << "Failed line " << __LINE__ << '\n'; std::abort(); } } while (false)
int main() {
  using namespace doc_capture;
  CHECK(FitSize(1280,720,960).width == 960);
  CHECK(FitSize(1280,720,960).height == 540);
  CHECK(FitSize(64,48,1280).width == 64);
  CHECK(FitSize(720,1280,640).width == 360);
  CHECK(FitSize(-1,720,640).width == 0);
  CHECK(FitSize(100000,100000,640).width == 0);
  CHECK(FitSize(1280,720,1281).width == 0);
  std::vector<uint8_t> input(4*4*4);
  for (size_t i=0;i<input.size();++i) input[i]=static_cast<uint8_t>(i);
  std::vector<uint8_t> output(4*4*4+2, 213);
  SampleSize size;
  CHECK(!SampleRgba(input.data(),input.size(),4,4,output.data()+1,15,2,true,&size));
  CHECK(output[1] == 213);
  CHECK(!SampleRgba(input.data(),1,4,4,output.data()+1,64,2,true,&size));
  CHECK(!SampleRgba(nullptr,64,4,4,output.data()+1,64,2,true,&size));
  CHECK(SampleRgba(input.data(),input.size(),4,4,output.data()+1,64,4,true,&size));
  for(size_t i=0;i<64;++i) CHECK(output[i+1] == (i%4==3 ? 255 : input[i]));
  CHECK(output.front()==213 && output.back()==213);
  std::fill(output.begin(),output.end(),static_cast<uint8_t>(213));
  CHECK(SampleRgba(input.data(),64,4,4,output.data()+1,16,2,true,&size));
  CHECK(output[1]==10 && output[2]==11 && output[3]==12 && output[4]==255);
  CHECK(output[16]==255 && output[17]==213);
  CHECK(SampleRgba(input.data(),64,4,4,output.data()+1,16,2,false,&size));
  CHECK(output[1]==0 && output[5]==8 && output[9]==32);
  for (const auto dims : {SampleSize{2592,1944}, SampleSize{3264,2448}, SampleSize{2448,3264}}) {
    std::vector<uint8_t> large(static_cast<size_t>(dims.width)*dims.height*4, 100);
    for (int maximum : {640,960,1280}) {
      const auto expected=FitSize(dims.width,dims.height,maximum);
      const size_t bytes=static_cast<size_t>(expected.width)*expected.height*4;
      std::vector<uint8_t> bounded(bytes+2,213);
      const auto started=std::chrono::steady_clock::now();
      for(int i=0;i<10;++i) CHECK(SampleRgba(large.data(),large.size(),dims.width,dims.height,
        bounded.data()+1,bytes,maximum,true,&size));
      CHECK(size.width==expected.width && size.height==expected.height);
      CHECK(bounded[1]==100 && bounded[4]==255 && bounded[bytes]==255);
      CHECK(bounded.front()==213 && bounded.back()==213);
      std::cout << "native_sample " << dims.width << 'x' << dims.height << " max=" << maximum
        << " mean_ms=" << std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count()/10 << '\n';
    }
  }
  std::cout << "sampler bounds/pixels/5MP/8MP/portrait PASS\n";
}
