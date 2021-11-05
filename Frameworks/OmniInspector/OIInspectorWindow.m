// Copyright 2002-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIInspectorWindow.h>

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniInspector/OIInspectorRegistry.h>

@implementation OIInspectorWindow

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag;
{
    if (!(self = [super initWithContentRect:contentRect styleMask:aStyle backing:bufferingType defer:flag]))
        return nil;
    [self setAutorecalculatesKeyViewLoop:YES];
    [self setHasShadow:YES];
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

    id <OIInspectorWindowDelegate> delegate = (id)[self delegate];
    OBASSERT([delegate conformsToProtocol:@protocol(OIInspectorWindowDelegate)]);
    
    if (currentFrame.size.height != newFrame.size.height || currentFrame.size.width != newFrame.size.width)
        newFrame = [delegate windowWillResizeFromFrame:currentFrame toFrame:newFrame];
    [super setFrame:newFrame display:display animate:animate];

    [delegate windowDidFinishResizing:self];
}

- (void)recalculateKeyViewLoop;
{
    // for some reason, this is called when the window is loaded despite the autorecalculatesKeyViewLoop
    if ([self autorecalculatesKeyViewLoop])
	[super recalculateKeyViewLoop];
}

@end
