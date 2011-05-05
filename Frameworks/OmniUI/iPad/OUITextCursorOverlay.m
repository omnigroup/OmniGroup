// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUITextCursorOverlay.h"

#import <OmniUI/OUIEditableFrame.h>

RCS_ID("$Id$");

@implementation OUITextCursorOverlay

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    
    self.opaque = NO;
    self.backgroundColor = nil;
    self.foregroundColor = [UIColor redColor];
    self.clearsContextBeforeDrawing = YES;
    
    [self setNeedsDisplay];
    
    _subpixelFrame = (CGRect){ {0, 0}, frame.size };
    
    return self;
}

- (void)dealloc;
{
    [_foregroundColor release];
    [super dealloc];
}

- (void)startBlinking;
{
    if (self.hidden)
        return;
    
    [UIView beginAnimations:@"OUITextCursorOverlayBlink" context:NULL];
    {
        [UIView setAnimationDuration:.5];
        [UIView setAnimationDelay:.25];
        [UIView setAnimationDelegate:self];
        [UIView setAnimationRepeatAutoreverses:YES];
        [UIView setAnimationRepeatCount:FLT_MAX];
        self.alpha = 0;
    }
    [UIView commitAnimations];
}

- (void)stopBlinking;
{
    [UIView beginAnimations:@"OUITextCursorOverlayBlink" context:NULL];
    {
        [UIView setAnimationRepeatCount:1];
        [UIView setAnimationBeginsFromCurrentState:YES];
        self.alpha = 1;
    }
    [UIView commitAnimations];
}

- (void)setCursorFrame:(CGRect)cursorFrame;
{
    BOOL wasAnimating = [UIView areAnimationsEnabled];
    @try {
        if (wasAnimating)
            [UIView setAnimationsEnabled:NO];
        CGRect actualFrame = CGRectIntegral(cursorFrame);
        self.frame = actualFrame;
        CGRect bounds = self.bounds;
        _subpixelFrame = (CGRect){ {cursorFrame.origin.x - actualFrame.origin.x + bounds.origin.x,
                                    cursorFrame.origin.y - actualFrame.origin.y + bounds.origin.y },
                                   cursorFrame.size };
        [self setNeedsDisplay];
    } @finally {
        OBASSERT(![UIView areAnimationsEnabled]); // Make sure something hasn't turned it on again, like -[UIToolbar setItem:] (Radar 8496247)
        if (wasAnimating)
            [UIView setAnimationsEnabled:YES];
    }
}

@synthesize foregroundColor = _foregroundColor;

#pragma mark -
#pragma mark UIView

- (void)drawRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGContextSetFillColorWithColor(ctx, [_foregroundColor CGColor]);
    CGContextFillRect(ctx, _subpixelFrame);
}

@end
