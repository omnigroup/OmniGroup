// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSSplitView-OAExtensions.h 104581 2008-09-06 21:18:23Z kc $

#import <AppKit/NSSplitView.h>

@interface NSSplitView (OAExtensions)
- (float)fraction;
- (void)setFraction:(float)newFract;
- (int)topPixels;
- (void)setTopPixels:(int)newTop;
- (int)bottomPixels;
- (void)setBottomPixels:(int)newBottom;

- (void)animateSubviewResize:(NSView *)resizingSubview startValue:(float)startValue endValue:(float)endValue;

@end
