// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSSplitView-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation NSSplitView (OAExtensions)

// FI_TSplitView in FinderKit.framework defines this method, but with an unsigned argument.
- (CGFloat)oa_positionOfDividerAtIndex:(NSInteger)dividerIndex;
{
    // It looks like NSSplitView relies on its subviews being ordered left->right or top->bottom so we can too.  It also raises w/ array bounds exception if you use its API with dividerIndex > count of subviews.
    while (dividerIndex >= 0 && [self isSubviewCollapsed:[[self subviews] objectAtIndex:dividerIndex]])
        dividerIndex--;
    if (dividerIndex < 0)
        return 0.0f;
    
    NSRect priorViewFrame = [[[self subviews] objectAtIndex:dividerIndex] frame];
    return [self isVertical] ? NSMaxX(priorViewFrame) : NSMaxY(priorViewFrame);
}

- (CGFloat)fraction;
{
    NSRect topFrame, bottomFrame;

    if ([[self subviews] count] < 2)
	return 0.0f;

    if ([self isSubviewCollapsed:[[self subviews] objectAtIndex:0]])
        topFrame = NSZeroRect;
    else
        topFrame = [[[self subviews] objectAtIndex:0] frame];
    
    if ([self isSubviewCollapsed:[[self subviews] objectAtIndex:1]])
        bottomFrame = NSZeroRect;
    else
        bottomFrame = [[[self subviews] objectAtIndex:1] frame];
    
    if (topFrame.origin.y != bottomFrame.origin.y)
	return bottomFrame.size.height / (bottomFrame.size.height + topFrame.size.height);
    else
	return bottomFrame.size.width / (bottomFrame.size.width + topFrame.size.width);
}

- (void)animateSubviewResize:(NSView *)resizingSubview startValue:(CGFloat)startValue endValue:(CGFloat)endValue;
{
    OBASSERT([resizingSubview superview] == self);
    
    BOOL shouldAnimate = [[self window] isVisible];
    
    NSRect currentFrame, startingFrame, endingFrame;
    currentFrame = [resizingSubview frame];
    
    if ([self isVertical]) {
	startingFrame = (NSRect){currentFrame.origin, NSMakeSize(startValue, currentFrame.size.height)};
	endingFrame = (NSRect){currentFrame.origin, NSMakeSize(endValue, currentFrame.size.height)};
    } else {
	startingFrame = (NSRect){currentFrame.origin, NSMakeSize(currentFrame.size.width, startValue)};
	endingFrame = (NSRect){currentFrame.origin, NSMakeSize(currentFrame.size.width, endValue)};
    }
    
    NSDictionary *animationDictionary = [NSDictionary dictionaryWithObjectsAndKeys:resizingSubview, NSViewAnimationTargetKey, [NSValue valueWithRect:endingFrame], NSViewAnimationEndFrameKey, [NSValue valueWithRect:startingFrame], NSViewAnimationStartFrameKey, nil];
    NSMutableArray *animationArray = [NSMutableArray arrayWithObject:animationDictionary];
    NSAnimation *animation = [[NSViewAnimation alloc] initWithViewAnimations:animationArray];
    
    id <NSAnimationDelegate> delegate = (id)[self delegate]; // Let our delegate implement some of the animation delegate methods if it wants
    [animation setDelegate:delegate];
    [animation setAnimationBlockingMode:NSAnimationBlocking];
    [animation setDuration:shouldAnimate ? 0.25 : 0.0];
    [animation startAnimation];
    [animation release];
}

#ifdef DEBUG

static id SplitViewDidResizeObserver;

OBDidLoad(^{
    SplitViewDidResizeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSSplitViewDidResizeSubviewsNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSSplitView *splitView = note.object;
        for (NSView *subview in splitView.subviews) {
            CGRect subviewFrame = subview.frame;
            
            // NSIntegralRect returns CGRectZero if called with something with zero width (and maybe height).
            if (subviewFrame.size.width == 0 || subviewFrame.size.height == 0)
                continue;
            
            BOOL isPixelAligned = NSEqualRects(subviewFrame, [subview backingAlignedRect:subviewFrame options:NSAlignAllEdgesNearest]);
            if (!isPixelAligned) {
                static NSString *const AlreadyWarnedKey = @"OASplitViewIntegralWarning";
                id alreadyWarned = objc_getAssociatedObject(splitView, AlreadyWarnedKey);
                if (!alreadyWarned) {                    
                    OBASSERT_NOT_REACHED("Subview %@ of split view %@ was left with a nonintegral frame %@ after resize. Bad things can result when this happens. You should implement -[<NSSplitViewDelegate> splitView:constrainSplitPosition:ofSubviewAt:dividerIndex:] to restrict the splitters to integral positions. Only warning once per split view.", subview.shortDescription, splitView.shortDescription, NSStringFromRect(subviewFrame));
                    
                    objc_setAssociatedObject(splitView, AlreadyWarnedKey, [NSSplitView class], OBJC_ASSOCIATION_ASSIGN);
                    break;
                }
            }
        }
    }];
});

#endif

@end
