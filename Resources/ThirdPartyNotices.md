# Third-Party Notices

## Depth Anything V2 Small Core ML

- Source: `apple/coreml-depth-anything-v2-small`
- Model file: `DepthAnythingV2SmallF16.mlpackage`
- License: Apache-2.0
- License text: `Apache-2.0.txt` in this app's Resources directory
- URL: https://huggingface.co/apple/coreml-depth-anything-v2-small

This app uses the Apple-published Core ML conversion of Depth Anything V2 Small
to generate the on-device relative-depth feature used by the fixed posture pipeline.

## PoseNet MobileNet 0.75

- Source: Apple sample “Detecting Human Body Poses in an Image”
- Model file: `PoseNetMobileNet075S16FP16.mlmodel`
- Model license: Apache-2.0
- Sample code license: MIT
- License text: `Apache-2.0.txt` in this app's Resources directory
- URL: https://developer.apple.com/documentation/coreml/detecting-human-body-poses-in-an-image

This app uses the PoseNet model from Apple’s Core ML sample as its primary
on-device upper-body landmark extractor, with the system Vision request as a fallback.
