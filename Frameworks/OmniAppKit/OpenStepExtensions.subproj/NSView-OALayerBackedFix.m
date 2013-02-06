// Copyright 2000-2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSView-OALayerBackedFix.h>
#import <QuartzCore/CATransaction.h>

RCS_ID("$Id$");

@implementation NSView (OALayerBackedFix)

- (void)fixLayerGeometry;
{
    if (![self layer])
        return;
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
        
    for (NSView *subview in [self subviews]) {
        CALayer *layer = [subview layer];
#if 1
        CGPoint layerPosition = NSPointToCGPoint([self convertPointToBase:[subview frame].origin]);
#else
        // This version worked until 10.7.4 final, which seems to have broken convertPointToBacking for layer-hosted views. Switched to using the deprecated convertPointToBase for the time being. <bug:///80553> (Remove use of deprecated API in NSView-OOLayerBackedFix.m) 
        CGPoint layerPosition;
#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7 && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7
        layerPosition = NSPointToCGPoint([self convertPointToBacking:[subview frame].origin]);
#else
    #if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7
        {
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                OBASSERT_NOT_REACHED("We don't want to support building against the 10.7 SDK targeting 10.6. This will become a hard compile error in the future.");
            });
        }
    #endif
        layerPosition = NSPointToCGPoint([self convertPointToBase:[subview frame].origin]);
#endif
#endif
        layer.position = layerPosition;
    }
        
    [CATransaction commit];
}

@end
