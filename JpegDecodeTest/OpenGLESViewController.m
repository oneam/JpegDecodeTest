//
//  OpenGLESViewController.m
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

#import "OpenGLESViewController.h"
#import <QuartzCore/QuartzCore.h>
#include "turbojpeg.h"


#define STRINGIZE(x) #x
#define STRINGIZE2(x) STRINGIZE(x)
#define SHADER_STRING(text) @ STRINGIZE2(text)

NSString *const vertexShaderString = SHADER_STRING
(
    attribute vec4 position;
    attribute vec4 texcoord_a;
    varying vec2 texcoord;

    void main()
    {
        gl_Position = position;
        texcoord = texcoord_a.xy;
    }
);

/*
 From Rec. ITU-R BT.2020
 Y' = 0.2627R' + 0.6780G' + 0.0593B'
 Cb' = (B' - Y')/1.4746
 Cr' = (R' - Y')/1.8814
 
 Derived
 R' = Y' + 1.8814Cr'
 G' = Y' + 0.7290Cr' + 0.1290Cb'
 B' = Y'             + 1.4746Cb'
 */

NSString *const fragmentShaderString = SHADER_STRING
(
    varying highp vec2 texcoord;
                                                         
    uniform sampler2D ySampler;
    uniform sampler2D uSampler;
    uniform sampler2D vSampler;
 
    uniform int yEnabled;
    uniform int uEnabled;
    uniform int vEnabled;

    const mediump mat4 yuv2rgb = mat4(1.0, 1.8814, 0.0000, 0.0,
                                      1.0, 0.7290, 0.1290, 0.0,
                                      1.0, 0.0000, 1.4746, 0.0,
                                      0.0, 0.0000, 0.0000, 1.0);

    void main()
    {
        mediump vec4 yuv = vec4(0.0, 0.0, 0.0, 1.0);
        
        if(yEnabled > 0) yuv.r = texture2D(ySampler, texcoord).r;
        if(uEnabled > 0) yuv.g = texture2D(uSampler, texcoord).r - 0.5;
        if(vEnabled > 0) yuv.b = texture2D(vSampler, texcoord).r - 0.5;
        
        mediump vec4 rgb = yuv * yuv2rgb;

        gl_FragColor = rgb;
    }
);

static BOOL validateProgram(GLuint prog)
{
	GLint status;
    
    glValidateProgram(prog);
    
#ifdef DEBUG
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == GL_FALSE) {
		NSLog(@"Failed to validate program %d", prog);
        return NO;
    }
    
	return YES;
}

static GLuint compileShader(GLenum type, NSString *shaderString)
{
	GLint status;
	const GLchar *sources = (GLchar *)shaderString.UTF8String;
    
    GLuint shader = glCreateShader(type);
    if (shader == 0 || shader == GL_INVALID_ENUM) {
        NSLog(@"Failed to create shader %d", type);
        return 0;
    }
    
    glShaderSource(shader, 1, &sources, NULL);
    glCompileShader(shader);
    
#ifdef DEBUG
	GLint logLength;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (status == GL_FALSE) {
        glDeleteShader(shader);
		NSLog(@"Failed to compile shader:\n");
        return 0;
    }
    
	return shader;
}

static const GLfloat positionVertices[] = {
    -1.0f, -1.0f,
     1.0f, -1.0f,
    -1.0f,  1.0f,
     1.0f,  1.0f,
};

static const GLfloat texcoordVertices[] = {
     0.0f, 1.0f,
     1.0f, 1.0f,
     0.0f, 0.0f,
     1.0f, 0.0f,
};

@interface OpenGLESViewController ()
{
    GLuint _programRef;
    
    GLuint _positionRef;
    GLuint _positionBufferRef;
    
    GLuint _texcoordRef;
    GLuint _texcoordBufferRef;

    GLuint _samplerRef[3];
    GLuint _textureRef[3];
    GLuint _enabledRef[3];
    
    NSData *_jpegData;
}

@property tjhandle decoder;
@property CAEAGLLayer *renderLayer;
@property EAGLContext *context;

@end

@implementation OpenGLESViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self initDecoder];
    [self initGLKView];
    [self compileShader];
    [self loadBuffers];
    [self initTextures];
}

- (void)initDecoder
{
    self.decoder = tjInitDecompress();
}

- (void)initGLKView
{
    GLKView *view = (GLKView *)self.imageView;
    view.delegate = self;
    view.enableSetNeedsDisplay = YES;
    
    EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!context) {
        NSLog(@"failed to create context");
        return;
    }

    if(![EAGLContext setCurrentContext:context]) {
        NSLog(@"failed to setup context");
        return;
    }
    
    view.context = context;
    self.context = context;

    view.drawableColorFormat = GLKViewDrawableColorFormatRGBA8888;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    view.drawableStencilFormat = GLKViewDrawableStencilFormat8;
}

- (void)compileShader
{
    GLuint vertexShader = compileShader(GL_VERTEX_SHADER, vertexShaderString);
	if (!vertexShader) return;
    
	GLuint fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragmentShaderString);
    if (!fragmentShader) return;
    
    _programRef = glCreateProgram();
	glAttachShader(_programRef, vertexShader);
	glAttachShader(_programRef, fragmentShader);
	glLinkProgram(_programRef);
    
    GLint status;
    glGetProgramiv(_programRef, GL_LINK_STATUS, &status);
    if (status == GL_FALSE) {
		NSLog(@"Failed to link program %d", _programRef);
        return;
    }

    _positionRef = glGetAttribLocation(_programRef, "position");
    _texcoordRef = glGetAttribLocation(_programRef, "texcoord_a");
    
    _samplerRef[0] = glGetUniformLocation(_programRef, "ySampler");
    _samplerRef[1] = glGetUniformLocation(_programRef, "uSampler");
    _samplerRef[2] = glGetUniformLocation(_programRef, "vSampler");
    
    _enabledRef[0] = glGetUniformLocation(_programRef, "yEnabled");
    _enabledRef[1] = glGetUniformLocation(_programRef, "uEnabled");
    _enabledRef[2] = glGetUniformLocation(_programRef, "vEnabled");
}

- (void)loadBuffers
{
    glGenBuffers(1, &_positionBufferRef);
    glBindBuffer(GL_ARRAY_BUFFER, _positionBufferRef);
    glBufferData(GL_ARRAY_BUFFER, 2 * 4 * sizeof(float), positionVertices, GL_STATIC_DRAW);
    glEnableVertexAttribArray(_positionRef);
    glVertexAttribPointer(_positionRef, 2, GL_FLOAT, GL_FALSE, 0, 0);
    
    glGenBuffers(1, &_texcoordBufferRef);
    glBindBuffer(GL_ARRAY_BUFFER, _texcoordBufferRef);
    glBufferData(GL_ARRAY_BUFFER, 2 * 4 * sizeof(float), texcoordVertices, GL_STATIC_DRAW);
    glEnableVertexAttribArray(_texcoordRef);
    glVertexAttribPointer(_texcoordRef, 2, GL_FLOAT, GL_FALSE, 0, 0);
}

- (void)initTextures
{
    glGenTextures(3, _textureRef);

    for(int i = 0; i < 3; ++i)
    {
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, _textureRef[i]);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
}

- (void)dealloc
{
    tjDestroy(_decoder);
    glDeleteProgram(_programRef);
    glDeleteTextures(3, _textureRef);
    glDeleteBuffers(1, &_positionBufferRef);
    glDeleteBuffers(1, &_texcoordBufferRef);
}

- (void)decodeImageFromData:(NSData *)jpegData
{
    _jpegData = jpegData;
    [self.imageView setNeedsDisplay];
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    if(!_jpegData) return;
    
    int status;
    int width, height, subsamp;
    UInt8* jpegBuf = (UInt8*)(_jpegData.bytes);
    UInt64 jpegSize = _jpegData.length;
    
    status = tjDecompressHeader2(self.decoder, jpegBuf, jpegSize, &width, &height, &subsamp);
    
    if(status < 0)
    {
        NSLog(@"%s", tjGetErrorStr());
        return;
    }
    
    int uvWidth, uvHeight;
    BOOL uvEnabled;
    
    switch(subsamp)
    {
        case TJ_411:
            uvWidth = width/2;
            uvHeight = height/2;
            uvEnabled = YES;
            break;
        case TJ_444:
            uvWidth = width;
            uvHeight = height;
            uvEnabled = YES;
            break;
        case TJ_GRAYSCALE:
            uvWidth = 0;
            uvHeight = 0;
            uvEnabled = NO;
            break;
    }
    
    size_t yDataLength = width * height;
    size_t uDataLength = uvWidth * uvHeight;
    size_t vDataLength = uvWidth * uvHeight;
    size_t dataLength = yDataLength + uDataLength + vDataLength;
    
    NSMutableData *imageData = [NSMutableData dataWithLength:dataLength];
    UInt8* imageBuf = (UInt8*)(imageData.bytes);
    
    status = tjDecompressToYUV(self.decoder, jpegBuf, jpegSize, imageBuf, 0);
    
    if(status < 0)
    {
        NSLog(@"TurboJPEG error: %s", tjGetErrorStr());
        return;
    }
    
    UInt8* yBuf = (UInt8*)imageBuf;
    UInt8* uBuf = yBuf + yDataLength;
    UInt8* vBuf = uBuf + uDataLength;
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
	glUseProgram(_programRef);
    
    GLboolean textureEnabled[] = { YES, uvEnabled, uvEnabled };
    GLsizei textureWidth[] = { width, uvWidth, uvWidth };
    GLsizei textureHeight[] = { height, uvHeight, uvHeight };
    GLvoid* textureBuf[] = { yBuf, uBuf, vBuf };
    
    for(int i = 0; i < 3; ++i)
    {
        glUniform1i(_enabledRef[i], textureEnabled[i]);
        glUniform1i(_samplerRef[i], i);
        if(!textureEnabled[i]) continue;
        
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, _textureRef[i]);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, textureWidth[i], textureHeight[i], 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, textureBuf[i]);
    }

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    bool glError = false;
    GLenum glStatus = glGetError();
    while (glStatus != GL_NO_ERROR) {
        NSLog(@"GL error: %x", glStatus);
        glError = true;
        glStatus = glGetError();
    }
}

@end
