// Copyright 2002-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspectorWindow.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import "OIInspectorResizer.h"
#import "OIInspectorRegistry.h"

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniInspector/OIInspectorWindow.m 89466 2007-08-01 23:35:13Z kc $");

@interface OIInspectorWindow (Private)
@end

@implementation OIInspectorWindow

- (id)initWithContentRect:(NSRect)contentRect styleMask:(unsigned int)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag;
{
    if (![super initWithContentRect:contentRect styleMask:aStyle backing:bufferingType defer:flag])
        return nil;
    [self setHasShadow:YES];
    [self useOptimizedDrawing:YES];
    [self setLevel:NSFloatingWindowLevel];
    return self;
}

// NSWindow subclass

- (BOOL)canBecomeKeyWindow;
{
    return YES;
}

- (BOOL)_hasActiveControls; // private Apple method
{
    return YES;
}

- (NSTimeInterval)animationResizeTime:(NSRect)newFrame;
{
    return [super animationResizeTime:newFrame] * 0.33;
}

- (void)setFrame:(NSRect)newFrame display:(BOOL)display animate:(BOOL)animate;
{
    NSRect currentFrame = [self frame];

    if (currentFrame.size.height != newFrame.size.height || currentFrame.size.width != newFrame.size.width)
        newFrame = [[self delegate] windowWillResizeFromFrame:currentFrame toFrame:newFrame];	// Note that if we're being resized by the OAResizer, windowWillResizeFromFrame:toFrame: gets called multiple times, whereas windowDidFinishResizing only gets called when the OAResizer is completely done resizing us
    [super setFrame:newFrame display:display animate:animate];
    // Only tell our delegate that we're finished resizing if we're not in the midst of being resized by our resizer control.
    if (!_inspectorWindowFlags.isBeingResizedByResizer)
        [[self delegate] windowDidFinishResizing:self];
}

- (void)recalculateKeyViewLoop;
{
    // for some reason, this is called when the window is loaded despite the autorecalculatesKeyViewLoop
    if ([self autorecalculatesKeyViewLoop])
	[super recalculateKeyViewLoop];
}

@end


@implementation OIInspectorWindow (NotificationsDelegatesDatasources)

- (void)resizerWillBeginResizing:(OIInspectorResizer *)resizer;
{
    OBASSERT(_inspectorWindowFlags.isBeingResizedByResizer == NO);
    _inspectorWindowFlags.isBeingResizedByResizer = YES;
    [[self delegate] windowWillBeginResizing:self];
}

- (void)resizerDidFinishResizing:(OIInspectorResizer *)resizer;
{
    OBASSERT(_inspectorWindowFlags.isBeingResizedByResizer == YES);
    [[self delegate] windowDidFinishResizing:self];
    _inspectorWindowFlags.isBeingResizedByResizer = NO;
}

@end


@implementation OIInspectorWindow (Private)
@end
