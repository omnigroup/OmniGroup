// Copyright 2000-2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSView-OALayerBackedFix.h>
#import <OmniAppKit/OAVersion.h>

RCS_ID("$Id$");

#if defined(MAC_OS_X_VERSION_10_8) && MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_8

static void (*originalScrollToPoint)(id self, SEL _cmd, NSPoint newOrigin);

@implementation NSClipView (OALayerBackedFix)

+ (void)performPosing;
{
    if (NSAppKitVersionNumber < OAAppKitVersionNumber10_8)
        originalScrollToPoint = (void *)OBReplaceMethodImplementationWithSelector(self, @selector(scrollToPoint:), @selector(OALayerBackedFix_scrollToPoint:));
}

- (void)OALayerBackedFix_scrollToPoint:(NSPoint)newOrigin;
{
    originalScrollToPoint(self, _cmd, newOrigin);
    
    [self fixLayerGeometry];
    [[self subviews] makeObjectsPerformSelector:@selector(fixLayerGeometry)];
}

@end

#endif
