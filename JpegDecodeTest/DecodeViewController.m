//
//  DecodeViewController.m
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

#import "DecodeViewController.h"
#import <mach/mach.h>
#import <mach/mach_time.h>

const int kNumImages = 10;
const double kUpdateIntervalSeconds = 1.0;
static uint64_t sUpdateInterval = 0;
static NSArray *sImages;
const NSString *imageLock = @"ImageLock";

@interface DecodeViewController ()

@end

@implementation DecodeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	[DecodeViewController createImages];
}

- (void)viewWillAppear:(BOOL)animated
{
    [self startDecodeLoop];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self stopDecodeLoop];
}

- (void)updateFps
{
    double frameRate = (double)self.frameCount / kUpdateIntervalSeconds;
    NSLog(@"FPS: %f", frameRate);
    self.frameCount = 0;
    self.fpsLabel.text = [NSString stringWithFormat:@"%.0f", frameRate];
}

- (void)decodeNextImage
{
    NSData *data;
    
    @synchronized(imageLock)
    {
        if(!sImages) [DecodeViewController createImages];
        self.currentImageIndex = (self.currentImageIndex +1) % sImages.count;
        data = [sImages objectAtIndex:self.currentImageIndex];
    }
    
    [self decodeImageFromData:data];
    ++self.frameCount;
}

- (void)decodeImageFromData:(NSData*)data
{
    NSLog(@" This is a default implementation of decodeImageFromData. This should be overwritten in a subclass");
}

- (void)startDecodeLoop
{
    @synchronized(self)
    {
        self.decoding = YES;
        dispatch_queue_t decodeQueue = dispatch_get_main_queue();
        self.frameCount = 0;
        uint64_t lastUpdate = mach_absolute_time();
        
        if(sUpdateInterval == 0)
        {
            mach_timebase_info_data_t timebaseInfo;
            mach_timebase_info(&timebaseInfo);
            uint64_t updateIntervalNs = kUpdateIntervalSeconds * 1e9;
            sUpdateInterval = updateIntervalNs * timebaseInfo.denom / timebaseInfo.numer;
        }
        
        dispatch_async(decodeQueue, ^{ [self decodeAndUpdateFpsWithLastUpdate:lastUpdate]; });
    }
}

- (void)stopDecodeLoop
{
    @synchronized(self)
    {
        self.decoding = NO;
    }
}

- (void)decodeAndUpdateFpsWithLastUpdate:(uint64_t)lastUpdate
{
    if(!self.decoding) return;
    
    uint64_t now = mach_absolute_time();
    uint64_t elapsed = now - lastUpdate;
    
    if(elapsed > sUpdateInterval)
    {
        lastUpdate = now;
        [self updateFps];
    }
    
    [self decodeNextImage];

    dispatch_queue_t decodeQueue = dispatch_get_main_queue();
    dispatch_async(decodeQueue, ^{ [self decodeAndUpdateFpsWithLastUpdate:lastUpdate]; });
}

+ (void)createImages
{
    @synchronized(imageLock)
    {
        if(sImages) return;
        
        NSMutableArray *images = [NSMutableArray arrayWithCapacity:kNumImages];
        
        for(int i=0; i < kNumImages; ++i)
        {
            NSString *imageFilename = [NSString stringWithFormat:@"him%i", i+1];
            NSString *imagePath = [[NSBundle mainBundle] pathForResource:imageFilename ofType:@"jpg"];
            NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
            [images setObject:imageData atIndexedSubscript:i];
        }
        
        sImages = images;
    }
}

@end
