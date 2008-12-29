// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSImageRep.h>
#import <ApplicationServices/ApplicationServices.h>

@interface OICoreGraphicsImageRep : NSImageRep
{
    CGImageRef cgImage;
    NSString *colorSpaceName;
    id <NSObject> heldObject;
}

- initWithImageRef:(CGImageRef)myImage colorSpaceName:(NSString *)space;
- (void)setColorSpaceHolder:(id <NSObject>)anObject;
- (void)setImage:(CGImageRef)newImage;

@end
