// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>


@interface OUIOverlayView : UIView
{
@private
    NSString *_text;
    UIFont *_font;
    CGSize _borderSize;
    NSTimeInterval _messageDisplayInterval;
    
    NSTimer *_overlayTimer;
    CGSize _cachedSuggestedSize;
}

+ (void)displayTemporaryOverlayInView:(UIView *)view withString:(NSString *)string avoidingTouchPoint:(CGPoint)touchPoint;
+ (void)displayTemporaryOverlayInView:(UIView *)view withString:(NSString *)string centeredAbovePoint:(CGPoint)touchPoint displayInterval:(NSTimeInterval)displayInterval; 

- (void)displayTemporarilyInView:(UIView *)view;
- (void)displayInView:(UIView *)view;
- (void)hide;

- (CGSize)suggestedSize;

@property(retain,nonatomic) NSString *text;
@property(assign,nonatomic) CGSize borderSize;
@property(assign,nonatomic) NSTimeInterval messageDisplayInterval;  // seconds

- (void)avoidTouchPoint:(CGPoint)touchPoint withinBounds:(CGRect)superBounds;

@end
