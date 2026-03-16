# Malaysian License Plate Recognition

## Overview
This project is a MATLAB-based image processing system for detecting and recognizing Malaysian vehicle license plates from images. It applies plate detection, image enhancement, OCR, and character analysis techniques to extract plate text and infer the likely state or category from the detected plate prefix.

## Features
- License plate detection using MSER and image processing methods
- Plate region refinement for better OCR results
- OCR-based text recognition
- Character segmentation support
- Malaysian state inference from plate prefix
- Batch testing support for multiple images
- Military plate checking helper

## Technologies Used
- MATLAB
- Image Processing Toolbox
- Computer Vision Toolbox
- OCR functions

## Main Files
- `detectPlateMSER.m` - detects candidate license plate regions using MSER and fallback logic
- `enhancePlateForOCR.m` - improves plate image quality before OCR
- `readPlateOCR.m` - reads plate characters using OCR
- `recognizePlateText.m` - tries multiple preprocessing strategies to improve recognition
- `segmentPlateCharacters.m` - segments characters from the plate image
- `refinePlateBBox.m` - refines the detected plate bounding box
- `inferStateFromPlate.m` - identifies the probable Malaysian state from plate prefix
- `isMilitaryPlate.m` - checks whether the detected plate appears to be military
- `runBatchTest.m` - processes multiple images and exports results to CSV
- `IPPR.mlapp` - application interface file

## How It Works
1. Read a vehicle image
2. Detect possible plate regions
3. Refine the best plate bounding box
4. Enhance the cropped plate image
5. Apply OCR to extract text
6. Clean the detected text
7. Infer state or category from the plate prefix

## Example Use Cases
- Smart parking systems
- Traffic monitoring
- Access control systems
- Automated vehicle identification
- Academic image processing demonstrations

## How to Run
1. Open the project in MATLAB.
2. Make sure Image Processing Toolbox and Computer Vision Toolbox are installed.
3. Run the relevant script or app file.
4. For bulk testing, use `runBatchTest(imageFolder, cfg, outCsvPath, opts)`.

## Notes
- This repository does not include the full image dataset.
- Add your own sample vehicle images in the `sample-images` folder.
- Add screenshots of detection and OCR output to improve the project presentation on GitHub.

## Future Improvements
- Improve OCR accuracy for blurred or low-light images
- Support real-time video input
- Extend recognition to more plate formats
- Add a more polished end-user interface

## Author
Surya Prasanth Naidu
