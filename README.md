# convertor_tf_onnx_trt
tensorflow -> onnx -> tensorRT

## Build the image
- Follow https://stackoverflow.com/a/61737404
- Run
  ```bash
  docker build -t neilvaltec/convertor_tf_onnx_trt:0.0.1 .
  ```
## Run the contianer 
```bash
docker run -it --rm --gpus all neilvaltec/convertor_tf_onnx_trt:0.0.1 bash
```