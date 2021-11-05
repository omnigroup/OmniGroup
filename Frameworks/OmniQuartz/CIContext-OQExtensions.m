// Copyright 2005-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
//  Created by Timothy J. Wood on 8/31/05.

#import <OmniQuartz/CIContext-OQExtensions.h>
#if defined(MAC_OS_VERSION_11_0) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_11_0
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

RCS_ID("$Id$")

@implementation CIContext (OQExtensions)

// TODO: Change this to return an NSError.  I would have done that to start, but wasn't sure what to do about the domain.  This is mostly for debugging anyway.
- (BOOL)writePNGImage:(CIImage *)image fromRect:(CGRect)rect toURL:(NSURL *)url;
{
    CFStringRef typeIdentifier;
    if (@available(macOS 11, *)) {
        typeIdentifier = (CFStringRef)UTTypePNG.identifier;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        typeIdentifier = kUTTypePNG;
#pragma clang diagnostic pop
    }
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((CFURLRef)url, typeIdentifier, 1, NULL);
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
