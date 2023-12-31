FROM nvcr.io/nvidia/tensorflow:21.10-tf2-py3

ENV DEBIAN_FRONTEND=noninteractive
RUN apt update 

WORKDIR /workspace
COPY . .

#######################################
### Re-export tensorflow model. # REF: https://github.com/NVIDIA/TensorRT/blob/ba459b420e6f7bbebcdbe805f6ed1444a7e51f04/samples/python/tensorflow_object_detection_api/README.md?plain=1#L86C23-L86C23
RUN git clone https://github.com/tensorflow/models.git
WORKDIR /workspace/models
# checkout to commit 8d11677bb56dd6776ff14115aa7361bd04bbd0d8
RUN git checkout 8d11677bb56dd6776ff14115aa7361bd04bbd0d8
WORKDIR /workspace/models/research
RUN apt install -y protobuf-compiler
RUN protoc object_detection/protos/*.proto --python_out=.
RUN cp object_detection/packages/tf2/setup.py .
RUN python -m pip install --use-feature=2020-resolver .
RUN pip install protobuf==3.20.3

## script to test the installation 
RUN python object_detection/builders/model_builder_tf2_test.py
RUN pip show object-detection

WORKDIR /workspace
RUN mkdir re_export_tf
WORKDIR /workspace/re_export_tf
RUN mkdir export
# Take SSD as example. REF: https://github.com/NVIDIA/TensorRT/blob/main/samples/python/tensorflow_object_detection_api/README.md#tensorflow-saved-model
RUN wget http://download.tensorflow.org/models/object_detection/tf2/20200711/ssd_mobilenet_v2_320x320_coco17_tpu-8.tar.gz
RUN tar -xvf ssd_mobilenet_v2_320x320_coco17_tpu-8.tar.gz
WORKDIR /workspace/models/research/object_detection
RUN python exporter_main_v2.py \
        --input_type float_image_tensor \
        --trained_checkpoint_dir /workspace/re_export_tf/ssd_mobilenet_v2_320x320_coco17_tpu-8/checkpoint \
        --pipeline_config_path /workspace/re_export_tf/ssd_mobilenet_v2_320x320_coco17_tpu-8/pipeline.config \
        --output_directory /workspace/re_export_tf/export

#######################################
### Convert tf to onnx
WORKDIR /workspace 
RUN git clone https://github.com/NVIDIA/TensorRT.git
# checkout to release/8.6
WORKDIR /workspace/TensorRT
RUN git checkout release/8.6
WORKDIR /workspace/TensorRT/samples/python/tensorflow_object_detection_api
RUN pip install -r requirements.txt
RUN pip install nvidia-pyindex
RUN pip install onnx-graphsurgeon
RUN pip install numpy==1.23.0
RUN mkdir /workspace/onnx
RUN python create_onnx.py \
        --pipeline_config /workspace/re_export_tf/export/pipeline.config \
        --saved_model /workspace/re_export_tf/export/saved_model \
        --onnx /workspace/onnx/model.onnx

#######################################
### Convert onnx to tensorRT
RUN mkdir /workspace/trt
RUN nvidia-smi
RUN python build_engine.py \
    --onnx /workspace/onnx/model.onnx \
    --engine /workspace/trt/engine.trt \
    --precision fp16

#######################################
### Test model
RUN trtexec \
        --loadEngine=/workspace/trt/engine.trt \
        --useCudaGraph --noDataTransfers \
        --iterations=100 --avgRuns=100
        
RUN pip install Pillow==9.5.0
RUN mkdir /workspace/test_output
RUN python infer.py \
        --engine /workspace/trt/engine.trt \
        --input /workspace/images/resized/300x300_1.jpg \
        --output /workspace/test_output \
        --preprocessor fixed_shape_resizer \
        --labels /workspace/TensorRT/samples/python/tensorflow_object_detection_api/labels_coco.txt

## Results available at /workspace/test_output


#######################################
## install gstreamer compiled opencv
RUN pip uninstall -y opencv-python opencv-python-headless

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get install -y libsm6 libxext6 libxrender-dev python3-tk
RUN apt update && apt install -y pkg-config \
  ffmpeg \
  libavformat-dev \
  libavcodec-dev \
  libswscale-dev \
  cmake \
  libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-ugly \
  gstreamer1.0-rtsp \
  python3-dev \
  python3-numpy

RUN git clone --depth=1 -b 4.5.4 https://github.com/opencv/opencv
RUN cd opencv && \
    mkdir build && cd build && \
    cmake -D CMAKE_INSTALL_PREFIX=/usr -D WITH_GSTREAMER=ON .. && \
    make -j$(nproc)  && \
    make install 

#######################################
WORKDIR /workspace 
CMD /bin/bash