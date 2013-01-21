This is a study to determine the optimal method to decode and display single-use JPEG images on iPhone and iPad.

This code depends on libjpeg-turbo, available from http://libjpeg-turbo.virtualgl.org

4 methods are used to decode the same 10 JPEG images:
1. Creating a CGImage directly using a JPEGDataProvider and letting the CALayer decode it.
2. Forcing the CGImage to be decoded by drawing it into another CGImage.
3. Using TurboJpeg to decode and putting the results in a CGImage.
4. Using TurboJpeg to decode to YUV images and using OpenGL ES to combine those images onto the CALayer.
