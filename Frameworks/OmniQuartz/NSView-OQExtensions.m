// Copyright 2005-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
//  Created by Timothy J. Wood on 8/31/05.

#import <OmniQuartz/NSView-OQExtensions.h>

#import <OmniQuartz/CIContext-OQExtensions.h>
#import <OmniQuartz/OQTargetAnimation.h>

RCS_ID("$Id$")


NS_ASSUME_NONNULL_BEGIN

@implementation NSView (OQExtensions)

// Either view can be nil.  The frames of the two views are not changed.
// NOTE: This method seems to not work for WebViews since they draw w/o CSS information during fading (possibly since they've been marked as 'hidden')
- (void)fadeOutAndReplaceSubview:(nullable NSView *)oldSubview withView:(nullable NSView *)newSubview;
{
    if (oldSubview == newSubview)
	return;
    
    if (![[self window] isVisible]) {
	// Old view doesn't have a window or the window is off screen.  NSView -replaceSubview:with: doesn't like nil arguments.  The NSView method would preserve the ordering of the view relative to other subviews, but we don't in the case that we animate, so we don't bother to do so here either.
	[oldSubview removeFromSuperview];
	if (newSubview)
	    [self addSubview:newSubview];
    }
    
    NSMutableArray *animations = [NSMutableArray array];
    
    // NSViewAnimation will set the hidden bit on the view when fading out; we remember the old view's hidden bit and restore it (and will consider a hidden old view as being nil).
    BOOL oldSubviewHidden = [oldSubview isHidden];
    if (oldSubview && !oldSubviewHidden) {
	NSDictionary *animation = [[NSDictionary alloc] initWithObjectsAndKeys:
	    oldSubview, NSViewAnimationTargetKey,
	    NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey,
	    nil];
	[animations addObject:animation];
	[animation release];
    }
    
    if (newSubview) {
	OBASSERT(![newSubview isHidden]); // Fading in a hidden view?  Should we ignore it or should we unhide the view?
	NSDictionary *animation = [[NSDictionary alloc] initWithObjectsAndKeys:
	    newSubview, NSViewAnimationTargetKey,
	    NSViewAnimationFadeInEffect, NSViewAnimationEffectKey,
	    nil];
	[animations addObject:animation];
	[animation release];
	[self addSubview:newSubview];
    }

    if ([animations count]) {
	NSViewAnimation *animation = [[NSViewAnimation alloc] initWithViewAnimations:animations];	
	[animation setAnimationBlockingMode:NSAnimationBlocking];
	[animation setDuration:0.15f];
	[animation startAnimation];
	[animation release];
    }
    
    [oldSubview setHidden:oldSubviewHidden];
    [oldSubview removeFromSuperview];
}

// Converts the point to window coordinates, then calls CGContextSetPatternPhase().
- (void)setPatternColorReferencePoint:(NSPoint)point;
{
    NSPoint refPoint = [self convertPoint:point toView:nil];
    CGSize phase = (CGSize){refPoint.x, refPoint.y};
    CGContextSetPatternPhase([[NSGraphicsContext currentContext] graphicsPort], phase);
}


@end

NS_ASSUME_NONNULL_END
