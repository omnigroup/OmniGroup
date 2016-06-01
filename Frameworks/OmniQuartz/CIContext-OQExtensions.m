// Copyright 2005-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
//  Created by Timothy J. Wood on 8/31/05.

#import <OmniQuartz/CIContext-OQExtensions.h>

#import <OpenGL/gl.h>

RCS_ID("$Id$")

@implementation CIContext (OQExtensions)

- (void)fillRect:(CGRect)rect withColor:(CIColor *)color;
{
    // TODO: NOT a fan of this, but drawing a clear image isn't working for me...
#warning TJW: Maybe I need to turn off alpha test or something of the like?
    OBPRECONDITION([NSOpenGLContext currentContext]);
    
    if (!color || [color alpha] == 0.0) {
	// This is (probably) faster and for some reason doing a constant alpha=0 image doesn't actually draw, even when we have blending set to 1/0.  Pfeh.
	glScissor((GLint)CGRectGetMinX(rect), (GLint)CGRectGetMinY(rect), (GLsizei)CGRectGetWidth(rect), (GLsizei)CGRectGetHeight(rect));
	glEnable(GL_SCISSOR_TEST);
	glClear(GL_COLOR_BUFFER_BIT);
	glDisable(GL_SCISSOR_TEST);
    } else {
	static CIColor *clear;
	if (!clear)
	    clear = [[CIColor colorWithRed:0 green:0 blue:0 alpha:0] retain];
	
	CIFilter *constantColorGenerator = [CIFilter filterWithName:@"CIConstantColorGenerator"];
	[constantColorGenerator setValue:color ? color : clear forKey:@"inputColor"];
	
	// Crop the infinite color generator to the requested rect
	CIFilter *cropFilter = [CIFilter filterWithName:@"CICrop"];
	[cropFilter setValue:[constantColorGenerator valueForKey:@"outputImage"] forKey:@"inputImage"];
	[cropFilter setValue:[CIVector vectorWithX:CGRectGetMinX(rect) Y:CGRectGetMinY(rect) Z:CGRectGetWidth(rect) W:CGRectGetHeight(rect)] forKey:@"inputRectangle"];
	
	// Do the draw!  This should be fast since it is constant
	CIImage *constantColorImage = [cropFilter valueForKey:@"outputImage"];
	[self drawImage:constantColorImage inRect:rect fromRect:rect];
    }
}

// TODO: Change this to return an NSError.  I would have done that to start, but wasn't sure what to do about the domain.  This is mostly for debugging anyway.
- (BOOL)writePNGImage:(CIImage *)image fromRect:(CGRect)rect toURL:(NSURL *)url;
{
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((CFURLRef)url, kUTTypePNG, 1, NULL);
    if (!dest)
	return NO;
    
    CGImageRef destImage = [self createCGImage:image fromRect:rect];
    if (destImage) {
	CGImageDestinationAddImage(dest, destImage, NULL);
	CFRelease(destImage);
    } else {
	CFRelease(dest);
	return NO;
    }
    
    BOOL result = CGImageDestinationFinalize(dest) ? YES : NO; // bool -> BOOL, just in case.
    CFRelease(dest);
    return result;
}

@end
