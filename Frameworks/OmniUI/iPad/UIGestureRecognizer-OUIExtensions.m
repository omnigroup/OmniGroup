// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniUI/UIGestureRecognizer-OUIExtensions.h>

#if OUI_GESTURE_RECOGNIZER_DEBUG // For 'state' being readwrite
#import <UIKit/UIGestureRecognizerSubclass.h>
#endif
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation UIGestureRecognizer (OUIExtensions)

#if OUI_GESTURE_RECOGNIZER_DEBUG
static void (*original_setState)(UIGestureRecognizer *self, SEL _cmd, UIGestureRecognizerState state);

static NSString * const stateNames[] = {
    [UIGestureRecognizerStatePossible]  = @"    POSSIBLE",
    [UIGestureRecognizerStateBegan]     = @"       BEGAN",
    [UIGestureRecognizerStateChanged]   = @"     CHANGED",
    [UIGestureRecognizerStateEnded]     = @"       ENDED",
    [UIGestureRecognizerStateCancelled] = @"   CANCELLED",
    [UIGestureRecognizerStateFailed]    = @"      FAILED",
};

static NSString *_stringToLog(UIGestureRecognizer *self, NSString *message) {
    NSString *identifier = self.debugIdentifier;
    if (identifier == nil) {
        identifier = @": ";
    } else {
        identifier = [NSString stringWithFormat:@" “%@”: ", identifier];
    }
    return [NSString stringWithFormat:@"%@ recognizer%@%@", message, identifier, [self shortDescription]];
}

static void _logRecognizer(UIGestureRecognizer *self, NSString *message) {
    NSLog(@"%@", _stringToLog(self, message));
}

static void _replacement_setState(UIGestureRecognizer *self, SEL _cmd, UIGestureRecognizerState state)
{
    NSInteger nameCount = sizeof(stateNames)/sizeof(stateNames[0]); // always positive, but we use NSInteger to match UIGestureRecognizerState's underlying value type
    NSString *stateName = @"????";
    if (state < nameCount) {
        stateName = stateNames[state];
    }
    
    _logRecognizer(self, stateName);
    original_setState(self, _cmd, state);
    
    UIGestureRecognizerState acceptedState = self.state;
    if (acceptedState != state) {
        // The delegate gets called in -setState:UIGestureRecognizerStateBegan and can refuse to begin.
        _logRecognizer(self, stateName);
    }
}

static void (*original_setEnabled)(UIGestureRecognizer *self, SEL _cmd, BOOL enabled);

static void _replacement_setEnabled(UIGestureRecognizer *self, SEL _cmd, BOOL enabled)
{
    NSString *enabledness;
    if (enabled) {
        enabledness = @" ++ENABLED++";
    } else {
        enabledness = @"--DISABLED--";
    }
    
    _logRecognizer(self, enabledness);
    original_setEnabled(self, _cmd, enabled);
}

+ (void)enableStateChangeLogging;
{
    if (original_setState)
        return;
    original_setState = (typeof(original_setState))OBReplaceMethodImplementation([UIGestureRecognizer class], @selector(setState:), (IMP)_replacement_setState);
    original_setEnabled = (typeof(original_setEnabled))OBReplaceMethodImplementation([UIGestureRecognizer class], @selector(setEnabled:), (IMP)_replacement_setEnabled);
}
#endif

static void *debugIdentifierKey = &debugIdentifierKey;
- (nullable NSString *)debugIdentifier
{
#ifdef DEBUG
    id result = objc_getAssociatedObject(self, debugIdentifierKey);
    return OB_CHECKED_CAST_OR_NIL(NSString, result);
#else
    return nil;
#endif
}

- (void)setDebugIdentifier:(NSString *)debugIdentifier;
{
#ifdef DEBUG
    objc_setAssociatedObject(self, debugIdentifierKey, debugIdentifier, OBJC_ASSOCIATION_COPY);
#endif
    // otherwise no-op
}

- (nullable UIView *)hitView;
{
    UIView *view = self.view;
    CGPoint hitPoint = [self locationInView:view];
    return [view hitTest:hitPoint withEvent:nil];
}

- (nullable UIView *)nearestViewFromViews:(NSArray *)views relativeToView:(UIView *)comparisionView maximumDistance:(CGFloat)maximumDistance;
{
    CGPoint pt = [self locationInView:comparisionView];
    
    UIView *bestView = nil;
    CGFloat bestDistanceSqr = 0;
    CGFloat maximumDistanceSqr = maximumDistance * maximumDistance;
    
    for (UIView *candidate in views) {
        CGRect candidateRect = [candidate convertRect:candidate.bounds toView:comparisionView];
        
        CGPoint candidateOffset = CGPointMake(CGRectGetMidX(candidateRect) - pt.x, CGRectGetMidY(candidateRect) - pt.y);
        
        CGFloat candidateDistanceSqr = candidateOffset.x * candidateOffset.x + candidateOffset.y * candidateOffset.y;
        if (candidateDistanceSqr > maximumDistanceSqr)
            continue; // too far
        
        if (!bestView || candidateDistanceSqr < bestDistanceSqr) {
            bestView = candidate;
            bestDistanceSqr = candidateDistanceSqr;
        }
    }
    
    return bestView;
}

@end

#if OUI_GESTURE_RECOGNIZER_DEBUG

@implementation UIView (OUIGestureRecognizerExtensions)

- (void)logGestureRecognizers;
{
    NSMutableString *result = [NSMutableString new];
    [self _buildGestureRecognizerLog:result prefix:@""];
    NSLog(@"%@", result);
}

- (void)_buildGestureRecognizerLog:(NSMutableString *)log prefix:(NSString *)prefix;
{
    void(^addLine)(NSString *line) = ^(NSString *line){
        [log appendString:prefix];
        [log appendString:line];
        [log appendString:@"\n"];
    };
    addLine([NSString stringWithFormat:@"%@: ", [self class]]);
    
    for (UIGestureRecognizer *recognizer in self.gestureRecognizers) {
        addLine(_stringToLog(recognizer, @"->"));
    }
    
    NSString *newPrefix = [NSString stringWithFormat:@"  %@", prefix];
    for (UIView *view in self.subviews) {
        [view _buildGestureRecognizerLog:log prefix:newPrefix];
    }
}

@end
#endif

