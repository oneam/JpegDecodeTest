//
//  OpenGLESViewController.m
//  JpegDecodeTest
//
//  Created by Sam Leitch on 2013-06-19.
//  Copyright (c) 2013 Sam Leitch. All rights reserved.
//

#import "OpenGLESViewController.h"
#import <QuartzCore/QuartzCore.h>
#include "turbojpeg.h"

static void releaseData (void *info, const void *data, size_t size)
{
    free(info);
}

@interface OpenGLESViewController ()
@property tjhandle decoder;
@property CAEAGLLayer *renderLayer;
@end

@implementation OpenGLESViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.decoder = tjInitDecompress();
    
    self.renderLayer = [[CAEAGLLayer alloc] init];
    [self.imageView.layer addSublayer:self.renderLayer];
}

- (void)viewDidLayoutSubviews
{
    self.renderLayer.frame = self.imageView.layer.frame;
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
    
    size_t yCapacity = width * height;
    size_t uCapacity = width/2 * height/2;
    size_t vCapacity = width/2 * height/2;
    size_t capacity = yCapacity + uCapacity + vCapacity;
    
    unsigned char* imageData = calloc(capacity, sizeof(unsigned char));
    
    result = tjDecompressToYUV(self.decoder, jpegBuf, jpegSize, imageData, 0);
    if(result < 0)
    {
        NSLog(@"TurboJPEG error: %s", tjGetErrorStr());
        free(imageData);
        return;
    }
    
    // TODO: Add EAGL texture load and display.
}

@end
