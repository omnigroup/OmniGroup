// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@interface OUITextThumb : UIView
{
@private
    CGFloat ascent;          // Line ascent at the point of selection
    CGFloat width;           // Visual width of caret bar
    CGPoint touchdownPoint;  // Used during drag to compute touch deltas
    BOOL isEndThumb;         // Are we the start-thumb or the end-thumb?
}

@property (nonatomic, readwrite) BOOL isEndThumb;

- (void)setCaretRectangle:(CGRect)r;
- (CGFloat)distanceFromPoint:(CGPoint)p;

@end

