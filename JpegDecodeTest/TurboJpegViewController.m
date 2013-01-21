//
//  TurboJpegViewController.m
//  JpegDecodeTest
//
//  Copyright (c) 2013 Sam Leitch. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

#import "TurboJpegViewController.h"
#import <QuartzCore/QuartzCore.h>
#include "turbojpeg.h"

static void releaseData (void *info, const void *data, size_t size)
{
    free(info);
}

@interface TurboJpegViewController ()
@property tjhandle decoder;
@end

@implementation TurboJpegViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.decoder = tjInitDecompress();
}

- (void)decodeImageFromData:(NSData *)data
{
    unsigned char* jpegBuf = (unsigned char*)(data.bytes);
    unsigned long jpegSize = data.length;
    int width, height, jpegSubsamp;
    
    int result = tjDecompressHeader2(self.decoder, jpegBuf, jpegSize, &width, &height, &jpegSubsamp);
    if(result < 0)
    {
        NSLog(@"%s", tjGetErrorStr());
        return;
    }
    
    int pitch = width*4;
    size_t capacity = height*pitch;
    unsigned char* imageData = calloc(capacity, sizeof(unsigned char*));
    
    result = tjDecompress2(self.decoder, jpegBuf, jpegSize, imageData, width, pitch, height, TJPF_RGBX, 0);
    if(result < 0)
    {
        NSLog(@"%s", tjGetErrorStr());
        free(imageData);
        return;
    }
    
    CGDataProviderRef imageDataProvider = CGDataProviderCreateWithData(imageData, imageData, capacity, &releaseData);
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(width, height, 8, 32, pitch, colorspace, kCGBitmapByteOrderDefault | kCGImageAlphaLast, imageDataProvider, NULL, NO, kCGRenderingIntentDefault);
    
    self.imageView.layer.contents = (__bridge id)image;
    
    CGImageRelease(image);
    CGDataProviderRelease(imageDataProvider);
    CGColorSpaceRelease(colorspace);
}

@end
