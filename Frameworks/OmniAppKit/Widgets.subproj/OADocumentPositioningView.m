// Copyright 2002-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OADocumentPositioningView.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");


@interface OADocumentPositioningView (Private)
- (void)_positionDocumentView;
- (BOOL)_setDocumentView:(NSView *)value;
@end


@implementation OADocumentPositioningView

- (id)initWithFrame:(NSRect)frame;
{
    if ([super initWithFrame:frame] == nil)
        return nil;

    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    documentViewAlignment = NSImageAlignCenter;

    return self;
}

- (void)dealloc;
{
    [self _setDocumentView:nil];
    [super dealloc];
}

// API

- (NSView *)documentView;
{
    return documentView;
}

- (void)setDocumentView:(NSView *)value;
{
    if ([self _setDocumentView:value])
        [self _positionDocumentView];
}

- (NSImageAlignment)documentViewAlignment;
{
    return documentViewAlignment;
}

- (void)setDocumentViewAlignment:(NSImageAlignment)value;
{
    documentViewAlignment = value;
    [self _positionDocumentView];
}

// NSView subclass

- (void)resizeSubviewsWithOldSize:(NSSize)oldFrameSize;
{
    [super resizeSubviewsWithOldSize:oldFrameSize];
    [self _positionDocumentView];
}

@end


@implementation OADocumentPositioningView (NotificationsDelegatesDatasources)

- (void)_documentViewFrameChangedNotification:(NSNotification *)notification;
{
    [self _positionDocumentView];
    [self setNeedsDisplay:YES];	// we don't know what the old frame was, so we hav to be pessimistic about how much of us needs redisplay
}

@end


@implementation OADocumentPositioningView (Private)

- (void)_positionDocumentView;
{
    NSView *superview;
    NSSize contentSize;
    NSRect oldDocumentFrame;
    NSRect oldFrame;
    NSRect newFrame;
    
    superview = [self superview];
    if (superview == nil)
        return;
    contentSize = [superview bounds].size;
    
    if (documentView != nil)
        oldDocumentFrame = [documentView frame];
    else
        oldDocumentFrame = NSZeroRect;
    
    // ensure that our size is the greater of the scroll view's content size (visible content area) and our document view's size
    oldFrame = [self frame];
    newFrame = oldFrame;
    newFrame.size.width = MAX(oldDocumentFrame.size.width, contentSize.width);
    newFrame.size.height = MAX(oldDocumentFrame.size.height, contentSize.height);
    if (!NSEqualRects(newFrame, oldFrame)) {
        [self setFrame:newFrame];
        [[self superview] setNeedsDisplayInRect:NSUnionRect(oldFrame, newFrame)];
    }
    
    if (documentView != nil) {
        NSRect newDocumentFrame;
        
        newDocumentFrame = oldDocumentFrame;
        
        // calculate our desired frame, given the document view alignment setting
        switch (documentViewAlignment) {
            case NSImageAlignCenter:
                newDocumentFrame.origin.x = (newFrame.size.width - newDocumentFrame.size.width) / 2.0;
                newDocumentFrame.origin.y = (newFrame.size.height - newDocumentFrame.size.height) / 2.0;
                break;
            
            case NSImageAlignTop:
                newDocumentFrame.origin.x = (newFrame.size.width - newDocumentFrame.size.width) / 2.0;
                newDocumentFrame.origin.y = (newFrame.size.height - newDocumentFrame.size.height);
                break;
            
            case NSImageAlignTopLeft:
                newDocumentFrame.origin.x = 0.0;
                newDocumentFrame.origin.y = (newFrame.size.height - newDocumentFrame.size.height);
                break;
            
            case NSImageAlignTopRight:
                newDocumentFrame.origin.x = (newFrame.size.width - newDocumentFrame.size.width);
                newDocumentFrame.origin.y = (newFrame.size.height - newDocumentFrame.size.height);
                break;
            
            case NSImageAlignLeft:
                newDocumentFrame.origin.x = 0.0;
                newDocumentFrame.origin.y = (newFrame.size.height - newDocumentFrame.size.height) / 2.0;
                break;
            
            case NSImageAlignBottom:
                newDocumentFrame.origin.x = (newFrame.size.width - newDocumentFrame.size.width) / 2.0;
                newDocumentFrame.origin.y = 0.0;
                break;
            
            case NSImageAlignBottomLeft:
                newDocumentFrame.origin.x = 0.0;
                newDocumentFrame.origin.y = 0.0;
                break;
            
            case NSImageAlignBottomRight:
                newDocumentFrame.origin.x = (newFrame.size.width - newDocumentFrame.size.width);
                newDocumentFrame.origin.y = 0.0;
                break;
            
            case NSImageAlignRight:
                newDocumentFrame.origin.x = (newFrame.size.width - newDocumentFrame.size.width);
                newDocumentFrame.origin.y = (newFrame.size.height - newDocumentFrame.size.height) / 2.0;
                break;
                
            default:
                OBASSERT_NOT_REACHED("Unknown alignment value in documentViewAlignment");
                break;
        }
        
        // keep the frame on integral boundaries
        newDocumentFrame.origin.x = floor(newDocumentFrame.origin.x);
        newDocumentFrame.origin.y = floor(newDocumentFrame.origin.y);
        
        // if the frame has actually changed, set the new frame and mark the appropriate area as needing to be displayed
        if (!NSEqualPoints(newDocumentFrame.origin, oldDocumentFrame.origin)) {
            [documentView setFrameOrigin:newDocumentFrame.origin];
            [self setNeedsDisplayInRect:NSUnionRect(oldDocumentFrame, newDocumentFrame)];
        }
    }
}

- (BOOL)_setDocumentView:(NSView *)value;
{
    if (documentView == value)
        return NO;

    if (documentView != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self  name:NSViewFrameDidChangeNotification object:documentView];
        [documentView removeFromSuperview];
        [documentView release];
        documentView = nil;
    }

    if (value != nil) {
        documentView = [value retain];
        [self addSubview:documentView];
        [documentView setAutoresizingMask:NSViewNotSizable];	// so we will be told when our superview changes size, which might impact our frame
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_documentViewFrameChangedNotification:) name:NSViewFrameDidChangeNotification object:documentView];	// so we know when the document view changes size, which might impact our frame and/or the document view's position, and may mean we need to redisplay regardless
    }

    return YES;
}

@end
