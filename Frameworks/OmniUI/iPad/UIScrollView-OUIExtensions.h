// Copyright 2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIScrollView.h>

enum {
    OUIAutoscrollDirectionLeft = (1 << CGRectMinXEdge),
    OUIAutoscrollDirectionRight = (1 << CGRectMaxXEdge),
    OUIAutoscrollDirectionUp = (1 << CGRectMinYEdge),
    OUIAutoscrollDirectionDown = (1 << CGRectMaxYEdge),
} OUIAutoscrollDirection;

@interface UIScrollView (OUIExtensions)

@property(nonatomic,readonly) NSTimeInterval autoscrollTimerInterval;

- (BOOL)shouldAutoscrollWithRecognizer:(UIGestureRecognizer *)recognizer allowedDirections:(NSUInteger)allowedDirections;
- (BOOL)shouldAutoscrollWithRecognizer:(UIGestureRecognizer *)recognizer;

- (CGPoint)performAutoscrollWithRecognizer:(UIGestureRecognizer *)recognizer allowedDirections:(NSUInteger)allowedDirections;

@end
