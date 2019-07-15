// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIScrollView.h>

typedef enum {
    OUIAutoscrollDirectionLeft = (1 << CGRectMinXEdge),
    OUIAutoscrollDirectionRight = (1 << CGRectMaxXEdge),
    OUIAutoscrollDirectionUp = (1 << CGRectMinYEdge),
    OUIAutoscrollDirectionDown = (1 << CGRectMaxYEdge),
} OUIAutoscrollDirection;

@interface UIScrollView (OUIExtensions)

@property(nonatomic,readonly) NSTimeInterval autoscrollTimerInterval;

- (UIEdgeInsets)nonAutoScrollInsets:(NSUInteger)allowedDirections;
- (BOOL)shouldAutoscrollWithRecognizer:(UIGestureRecognizer *)recognizer allowedDirections:(NSUInteger)allowedDirections;
- (BOOL)shouldAutoscrollWithRecognizer:(UIGestureRecognizer *)recognizer;

- (CGPoint)performAutoscrollWithRecognizer:(UIGestureRecognizer *)recognizer allowedDirections:(NSUInteger)allowedDirections;

- (void)scrollRectToVisibleAboveLastKnownKeyboard:(CGRect)rect animated:(BOOL)animated completion:(void (^)(BOOL))completion;
- (void)adjustForKeyboardHidingWithPreferedFinalBottomContentInset:(CGFloat)bottomInset animated:(BOOL)animated;
- (void)animateAlongsideKeyboardHiding:(void(^)(void))animations;
- (CGFloat)minOffsetToScrollRectToVisible:(CGRect)rect aboveMinY:(CGFloat)minY;

@end
