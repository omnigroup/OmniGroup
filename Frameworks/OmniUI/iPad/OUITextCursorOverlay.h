// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@interface OUITextCursorOverlay : UIView
{
@private
    CGRect _subpixelFrame;
    UIColor *_foregroundColor;
}

- (void)startBlinking;
- (void)stopBlinking;

- (void)setCursorFrame:(CGRect)cursorFrame;
@property (readwrite, nonatomic, retain) UIColor *foregroundColor;

@end
