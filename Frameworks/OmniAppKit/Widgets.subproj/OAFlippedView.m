// Copyright 2007-2008, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAFlippedView.h"
#import <OmniAppKit/NSView-OALayerBackedFix.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

// Useful for nibs where you need a flipped container view that has nothing else special about it.
@implementation OAFlippedView

- (BOOL)isFlipped;
{
    return YES;
}

- (void)viewWillDraw;
{
    [super viewWillDraw];
    
    // HACK to work around rdar://probem/8009542 (CoreAnimation: Scroll view misbehaves with flipped layer-hosting document view). -_updateLayerGeometryFromView doesn't work with flipped views for some reason, but only on the first time around. If we reach the runloop and call it again (or scroll or do anything else to provoke it being called) then it lays out correctly. This is the cause of <bug://bugs/51584> (opening scrolled file doesn't draw outline view properly at first [CAOOV])
    
    if (!_triedLayerGeometryFix) {
        _triedLayerGeometryFix = YES;
        [self fixLayerGeometry];
    }
}

@end
