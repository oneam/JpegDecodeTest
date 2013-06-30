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

NSString *const fragmentShaderString = SHADER_STRING
(
    varying highp vec2 texcoord;
                                                         
    uniform sampler2D ySampler;
    uniform sampler2D uSampler;
    uniform sampler2D vSampler;
 
    uniform int yEnabled;
    uniform int uEnabled;
    uniform int vEnabled;

    uniform mediump mat4 yuv2rgb;

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

static const GLfloat yuv2rgb[] = {
    1.0f, 1.8814f, 0.0000f, 0.0f,
    1.0f, 0.7290f, 0.1290f, 0.0f,
    1.0f, 0.0000f, 1.4746f, 0.0f,
    0.0f, 0.0000f, 0.0000f, 1.0f,
};

@interface OpenGLESViewController ()
{
    GLuint _framebufferRef;
    GLuint _renderbufferRef;
    GLuint _programRef;
    
    GLuint _positionRef;
    GLuint _texcoordRef;
    GLint _yuv2rgbRef;

    GLuint _samplerRef[3];
    GLuint _textureRef[3];
    GLuint _enabledRef[3];
    
    GLint _viewportWidth;
    GLint _viewportHeight;
}

@property tjhandle decoder;
@property CAEAGLLayer *renderLayer;
@property EAGLContext *context;

@end

@implementation OpenGLESViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.decoder = tjInitDecompress();
    
    self.renderLayer = [[CAEAGLLayer alloc] init];
    self.renderLayer.opaque = YES;
    [self.imageView.layer addSublayer:self.renderLayer];

    EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    if (!context) {
        NSLog(@"failed to create context");
        return;
    }
    
    if(![EAGLContext setCurrentContext:context]) {
        NSLog(@"failed to setup context");
        return;
    }
    
    self.context = context;
    
    glGenFramebuffers(1, &_framebufferRef);
    glBindFramebuffer(GL_FRAMEBUFFER, _framebufferRef);
    
    glGenRenderbuffers(1, &_renderbufferRef);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbufferRef);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _renderbufferRef);

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
    _yuv2rgbRef = glGetUniformLocation(_programRef, "yuv2rgb");
    
    _samplerRef[0] = glGetUniformLocation(_programRef, "ySampler");
    _samplerRef[1] = glGetUniformLocation(_programRef, "uSampler");
    _samplerRef[2] = glGetUniformLocation(_programRef, "vSampler");
    
    _enabledRef[0] = glGetUniformLocation(_programRef, "yEnabled");
    _enabledRef[1] = glGetUniformLocation(_programRef, "uEnabled");
    _enabledRef[2] = glGetUniformLocation(_programRef, "vEnabled");
    
    glGenTextures(3, _textureRef);
}

- (void)dealloc
{
    tjDestroy(_decoder);
    glDeleteFramebuffers(1, &_framebufferRef);
    glDeleteRenderbuffers(1, &_renderbufferRef);
    glDeleteProgram(_programRef);
    glDeleteTextures(3, _textureRef);
}

- (void)viewDidLayoutSubviews
{
    CGRect frame = self.imageView.layer.frame;
    if(CGRectEqualToRect(frame, self.renderLayer.frame))
        return;
    
    self.renderLayer.frame = frame;
    
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbufferRef);
    [self.context renderbufferStorage:GL_RENDERBUFFER fromDrawable:self.renderLayer];
    
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_viewportWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_viewportHeight);
    glViewport(0, 0, _viewportWidth, _viewportHeight);
}

- (void)decodeImageFromData:(NSData *)jpegData
{
    if (_viewportWidth <= 0 || _viewportHeight <= 0) return;
    
    int status;
    GLenum glStatus = GL_NO_ERROR;
    int width, height, subsamp;
    UInt8* jpegBuf = (UInt8*)(jpegData.bytes);
    UInt64 jpegSize = jpegData.length;
    
    status = tjDecompressHeader2(self.decoder, jpegBuf, jpegSize, &width, &height, &subsamp);
    
    if(status < 0)
    {
        NSLog(@"%s", tjGetErrorStr());
        return;
    }
    
    int uvWidth, uvHeight;
    bool uvEnabled;
    
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

    UInt8* yBuf = imageBuf;
    UInt8* uBuf = yBuf + yDataLength;
    UInt8* vBuf = uBuf + uDataLength;
    
    [EAGLContext setCurrentContext:self.context];
    
    glBindFramebuffer(GL_FRAMEBUFFER, _framebufferRef);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
	glUseProgram(_programRef);
    
    glUniformMatrix4fv(_yuv2rgbRef, 1, GL_FALSE, yuv2rgb);
    
    glVertexAttribPointer(_positionRef, 2, GL_FLOAT, GL_FALSE, 0, positionVertices);
    glEnableVertexAttribArray(_positionRef);
    
    glVertexAttribPointer(_texcoordRef, 2, GL_FLOAT, GL_FALSE, 0, texcoordVertices);
    glEnableVertexAttribArray(_texcoordRef);
    
    GLboolean textureEnabled[] = { YES, uvEnabled, uvEnabled };
    GLsizei textureWidth[] = { width, uvWidth, uvWidth };
    GLsizei textureHeight[] = { height, uvHeight, uvHeight };
    GLvoid* textureBuf[] = { yBuf, uBuf, vBuf };

    for(int i = 0; i < 3; ++i)
    {
        glUniform1i(_enabledRef[i], textureEnabled[i]);
        if(!textureEnabled[i]) continue;
        
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, _textureRef[i]);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, textureWidth[i], textureHeight[i], 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, textureBuf[i]);
        glUniform1i(_samplerRef[i], i);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    bool glError = false;
    glStatus = glGetError();
    while (glStatus != GL_NO_ERROR) {
        NSLog(@"GL error: %x", status);
        glError = true;
        glStatus = glGetError();
    }
    
    if(glError) return;
    
    glStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (glStatus != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"GL framebuffer error: %x", status);
        return;
    }
    
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbufferRef);
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
}

@end
