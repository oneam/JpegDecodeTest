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
    
    uniform mediump mat4 yuv2rgb;

    void main()
    {
        highp float y = texture2D(ySampler, texcoord).r;
        highp float u = texture2D(uSampler, texcoord).r - 0.5;
        highp float v = texture2D(vSampler, texcoord).r - 0.5;
        
        mediump vec4 yuv = vec4(y, u, v, 1.0);
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

/* From Rec. ITU-R BT.2020
Y' = 0.2627R' + 0.6780G' + 0.0593B'
Cb' = (B' - Y')/1.4746
Cr' = (R' - Y')/1.8814
 */

static const GLfloat yuv2rgb[] = {
    1.0f, 0.0f, 0.0f, 0.0f,
    1.0f, 0.0f, 0.0f, 0.0f,
    1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 1.0f,
};

@interface OpenGLESViewController ()
@property tjhandle decoder;
@property CAEAGLLayer *renderLayer;

@property EAGLContext *context;
@property (assign) GLuint frameBufferRef;
@property (assign) GLuint renderBufferRef;
@property (assign) GLuint programRef;

@property (assign) GLuint yTextureRef;
@property (assign) GLuint uTextureRef;
@property (assign) GLuint vTextureRef;

@property (assign) GLuint positionRef;
@property (assign) GLuint texcoordRef;
@property (assign) GLint yuv2rgbRef;
@property (assign) GLuint ySamplerRef;
@property (assign) GLuint uSamplerRef;
@property (assign) GLuint vSamplerRef;

@property (assign) GLint viewportWidth;
@property (assign) GLint viewportHeight;
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
    
    GLuint frameBufferRef;
    glGenFramebuffers(1, &frameBufferRef);
    glBindFramebuffer(GL_FRAMEBUFFER, frameBufferRef);
    self.frameBufferRef = frameBufferRef;
    
    GLuint renderBufferRef;
    glGenRenderbuffers(1, &renderBufferRef);
    glBindRenderbuffer(GL_RENDERBUFFER, renderBufferRef);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, renderBufferRef);
    self.renderBufferRef = renderBufferRef;

    GLuint vertexShader = compileShader(GL_VERTEX_SHADER, vertexShaderString);
	if (!vertexShader) return;
    
	GLuint fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragmentShaderString);
    if (!fragmentShader) return;
    
    GLuint programRef = glCreateProgram();
	glAttachShader(programRef, vertexShader);
	glAttachShader(programRef, fragmentShader);
	glLinkProgram(programRef);
    self.programRef = programRef;
    
    GLint status;
    glGetProgramiv(programRef, GL_LINK_STATUS, &status);
    if (status == GL_FALSE) {
		NSLog(@"Failed to link program %d", programRef);
        return;
    }
    
    self.positionRef = glGetAttribLocation(programRef, "position");
    self.texcoordRef = glGetAttribLocation(programRef, "texcoord_a");
    self.yuv2rgbRef = glGetUniformLocation(programRef, "yuv2rgb");
    self.ySamplerRef = glGetUniformLocation(programRef, "ySampler");
    self.uSamplerRef = glGetUniformLocation(programRef, "uSampler");
    self.vSamplerRef = glGetUniformLocation(programRef, "vSampler");
    
    GLuint textures[3];
    glGenTextures(3, textures);
    self.yTextureRef = textures[0];
    self.uTextureRef = textures[1];
    self.vTextureRef = textures[2];

}

- (void)viewDidLayoutSubviews
{
    CGRect frame = self.imageView.layer.frame;
    self.renderLayer.frame = frame;
    
    glBindRenderbuffer(GL_RENDERBUFFER, self.renderBufferRef);
    [self.context renderbufferStorage:GL_RENDERBUFFER fromDrawable:self.renderLayer];
    
    GLint viewportWidth, viewportHeight;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &viewportWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &viewportHeight);
    self.viewportWidth = viewportWidth;
    self.viewportHeight = viewportHeight;
}

- (void)decodeImageFromData:(NSData *)jpegData
{
    if (self.viewportWidth <= 0 || self.viewportHeight <= 0) return;
    
    int status;
    int width, height, subsamp;
    UInt8* jpegBuf = (UInt8*)(jpegData.bytes);
    UInt64 jpegSize = jpegData.length;
    
    status = tjDecompressHeader2(self.decoder, jpegBuf, jpegSize, &width, &height, &subsamp);
    
    if(status < 0)
    {
        NSLog(@"%s", tjGetErrorStr());
        return;
    }
    
    int uvWidth = width/2;
    int uvHeight = height/2;
    
    size_t yDataLength = width * height;
    size_t uDataLength = uvWidth * uvHeight;
    size_t vDataLength = uvWidth * uvWidth;
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
    
    glBindFramebuffer(GL_FRAMEBUFFER, self.frameBufferRef);
    glViewport(0, 0, self.viewportWidth, self.viewportHeight);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
	glUseProgram(self.programRef);
    
    glUniformMatrix4fv(self.yuv2rgbRef, 1, GL_FALSE, yuv2rgb);
    
    glVertexAttribPointer(self.positionRef, 2, GL_FLOAT, GL_FALSE, 0, positionVertices);
    glEnableVertexAttribArray(self.positionRef);
    
    glVertexAttribPointer(self.texcoordRef, 2, GL_FLOAT, GL_FALSE, 0, texcoordVertices);
    glEnableVertexAttribArray(self.texcoordRef);
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, self.yTextureRef);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, width, height, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, yBuf);
    glUniform1i(self.ySamplerRef, 0);
    
//    glActiveTexture(GL_TEXTURE1);
//    glBindTexture(GL_TEXTURE_2D, self.uTextureRef);
//    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, uvWidth, uvHeight, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, uBuf);
//    glUniform1i(self.uSamplerRef, 1);
//    
//    glActiveTexture(GL_TEXTURE2);
//    glBindTexture(GL_TEXTURE_2D, self.vTextureRef);
//    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, uvWidth, uvHeight, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, vBuf);
//    glUniform1i(self.vSamplerRef, 2);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glBindRenderbuffer(GL_RENDERBUFFER, self.renderBufferRef);
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
}

@end
