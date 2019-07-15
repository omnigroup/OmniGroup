// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniUI/OUIKeyboardNotifier.h>
#import <OmniUI/UIView-OUIExtensions.h>

@import OmniFoundation;

#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
#define DEBUG_KEYBOARD(format, ...) NSLog(@"KEYBOARD: " format, ## __VA_ARGS__)
#else
#define DEBUG_KEYBOARD(format, ...)
#endif

NSString * const OUIKeyboardNotifierKeyboardWillChangeFrameNotification = @"OUIKeyboardNotifierKeyboardWillChangeFrameNotification";
NSString * const OUIKeyboardNotifierKeyboardDidChangeFrameNotification = @"OUIKeyboardNotifierKeyboardDidChangeFrameNotification";

NSString * const OUIKeyboardNotifierKeyboardWillShowNotification = @"OUIKeyboardNotifierKeyboardWillShowNotification";
NSString * const OUIKeyboardNotifierKeyboardDidShowNotification = @"OUIKeyboardNotifierKeyboardDidShowNotification";
NSString * const OUIKeyboardNotifierKeyboardWillHideNotification = @"OUIKeyboardNotifierKeyboardWillHideNotification";
NSString * const OUIKeyboardNotifierKeyboardDidHideNotification = @"OUIKeyboardNotifierKeyboardDidHideNotification";


NSString * const OUIKeyboardNotifierOriginalUserInfoKey = @"OUIKeyboardNotifierOriginalUserInfoKey";
NSString * const OUIKeyboardNotifierLastKnownKeyboardHeightKey = @"OUIKeyboardNotifierLastKnownKeyboardHeightKey";

typedef NS_ENUM(NSInteger, OUIKeyboardState) {
    OUIKeyboardStateUnknown = 0,
    OUIKeyboardStateAppearing,
    OUIKeyboardStateVisible,
    OUIKeyboardStateDisappearing,
    OUIKeyboardStateHidden
};

@interface OUIKeyboardNotifier ()

@property (nonatomic) OUIKeyboardState keyboardState;
@property (nonatomic, copy) NSDictionary *lastKnownKeyboardInfo;

@end

#pragma mark -

@implementation OUIKeyboardNotifier
{
    BOOL _needsUpdate;
}

static OUIKeyboardNotifier *sharedNotifier = nil;

+ (instancetype)sharedNotifier;
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedNotifier = [[OUIKeyboardNotifier alloc] init];
    });
    
    return sharedNotifier;
}

#ifdef DEBUG

+ (BOOL)hasSharedNotifier;
{
    return (sharedNotifier != nil);
}

#endif

- (id)init
{
    if (!(self = [super init]))
        return nil;

    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];

    [defaultCenter addObserver:self selector:@selector(_keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(_keyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(_keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(_keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    
    [defaultCenter addObserver:self selector:@selector(_keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(_keyboardDidChangeFrame:) name:UIKeyboardDidChangeFrameNotification object:nil];

    // We can't depend on the keyboard change notification happening before events like UIControlEventEditingDidBegin firing. So, we have a default value here that might be wrong on the first animation.
    _lastAnimationDuration = 0.25;
    _lastAnimationCurve = 7; // Doesn't match any entry in UIViewAnimationCurve ... ><
    
    return self;
}

- (BOOL)isKeyboardVisible;
{
    // REVIEW: Should OUIKeyboardStateDisappearing return YES or NO?
    
    switch (self.keyboardState) {
        case OUIKeyboardStateUnknown:
        case OUIKeyboardStateDisappearing:
        case OUIKeyboardStateHidden: {
            return NO;
        }
            
        case OUIKeyboardStateAppearing:
        case OUIKeyboardStateVisible:{
            return YES;
        }
    }
    
    OBASSERT_NOT_REACHED("Unhandled keyboardState case.");
    return NO;
}

- (void)setAccessoryToolbarView:(UIView *)accessoryToolbarView;
{
    if (_accessoryToolbarView == accessoryToolbarView)
        return;
    
    _accessoryToolbarView = accessoryToolbarView;
    _updateAccessoryToolbarViewFrame(self);
}

- (CGFloat)minimumYPositionOfLastKnownKeyboardInView:(UIView *)view;
{
    CGRect keyboardFrame = ((NSValue*)self.lastKnownKeyboardInfo[UIKeyboardFrameEndUserInfoKey]).CGRectValue;
    if (CGRectEqualToRect(keyboardFrame, CGRectZero)) {
        return CGRectGetMaxY(view.bounds);
    } else {
        keyboardFrame = [view convertRect:keyboardFrame fromView:nil];  // keyboard frame is in screen coordinates coming out of the dictionary
        return CGRectGetMinY(keyboardFrame);
    }
}

#pragma mark - Private

- (void)_keyboardWillShow:(NSNotification *)note;
{
    self.keyboardState = OUIKeyboardStateAppearing;
    DEBUG_KEYBOARD("keybard visibility state is now «appearing»");
    
    NSDictionary *userInfo = [note userInfo];
    _postNotification(self, OUIKeyboardNotifierKeyboardWillShowNotification, userInfo);
}

- (void)_keyboardDidShow:(NSNotification *)note;
{
    self.keyboardState = OUIKeyboardStateVisible;
    DEBUG_KEYBOARD("keybard visibility state is now «visible»");

    NSDictionary *userInfo = [note userInfo];
    _postNotification(self, OUIKeyboardNotifierKeyboardDidShowNotification, userInfo);
}

- (void)_keyboardWillHide:(NSNotification *)note;
{
    self.keyboardState = OUIKeyboardStateDisappearing;
    DEBUG_KEYBOARD("keybard visibility state is now «disappearing»");
    
    NSDictionary *userInfo = [note userInfo];
    _postNotification(self, OUIKeyboardNotifierKeyboardWillHideNotification, userInfo);
}

- (void)_keyboardDidHide:(NSNotification *)note;
{
    self.keyboardState = OUIKeyboardStateHidden;
    DEBUG_KEYBOARD("keybard visibility state is now «hidden»");
    
    // OUIKeyboardNotifier used to rely solely on frame changed notifications and (_lastKnownKeyboardHeight == 0) to determine if the keyboard was hidden or not.
    // It turns out that if the keyboard hides as a result of popping a navigation controller, the keyboard frame change notifications that you get leave you with the impression that the keyboard is still on screen even though it has slide to the right (not reflected by the end frame) and been removed from the screen.
    //
    // To avoid reporting the wrong value for isKeyboardVisible, we now listen to the keyboard appearance notifications and track that state separately.
    //
    // In the cast above, we'll be left with isKeyboardVisible=NO, but a lastKnownKeyboardHeight > 0, which doesn't make sense.
    // Assert that the keyboard height is 0, but correct it here, when the keyboard is dismissed.
    //
    // This should certainly be logged as a radar. We may wish to turn off this post condition if it generates too much noise.
    
//    OBPOSTCONDITION(_lastKnownKeyboardHeight == 0);
    _lastKnownKeyboardHeight = 0;

    NSDictionary *userInfo = [note userInfo];
    _postNotification(self, OUIKeyboardNotifierKeyboardDidHideNotification, userInfo);
    _lastKnownKeyboardInfo = nil;
}

- (void)_keyboardWillChangeFrame:(NSNotification *)note;
{
    DEBUG_KEYBOARD("will change frame %@", note);
    
    [self _handleKeyboardFrameChange:note isDid:NO];
}

- (void)_keyboardDidChangeFrame:(NSNotification *)note;
{
    DEBUG_KEYBOARD("did change frame %@", note);
    
    if ([self _handleKeyboardFrameChange:note isDid:YES]) {
        // Animation started from the did -- it will send the OUIMainViewControllerDidFinishResizingForKeyboard
    } else {
        // Otherwise they keyboard was driving the animation and it has finished, so we should do it now.
        NSDictionary *userInfo = [note userInfo];
        _postNotification(self, OUIKeyboardNotifierKeyboardDidChangeFrameNotification, userInfo);
    }
}

#pragma mark - Helpers

static void _postNotification(OUIKeyboardNotifier *self, NSString *notificationName, NSDictionary *originalInfo)
{
    // <bug:///113999> (Crasher: Crash in OUIKeyboardNotifiier attempting to insert nil object into dictionary)
    //
    // We have a ton of crashes from users because the originalInfo is nil. I'm not sure how this is happening (custom keyboards?) because it should always be present.
    // Let's avoid crashing if it is nil though.
    
    OBPRECONDITION(originalInfo != nil);
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[OUIKeyboardNotifierLastKnownKeyboardHeightKey] = @(self.lastKnownKeyboardHeight);
    
    if (originalInfo != nil) {
        userInfo[OUIKeyboardNotifierOriginalUserInfoKey] = originalInfo;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:self userInfo:userInfo];
}

- (BOOL)_handleKeyboardFrameChange:(NSNotification *)note isDid:(BOOL)isDid;
{
    _lastKnownKeyboardInfo = note.userInfo;
    
    CGFloat avoidedBottomHeight = _bottomHeightToAvoidForEndingKeyboardFrame(self, _lastKnownKeyboardInfo);
    if (_lastKnownKeyboardHeight == avoidedBottomHeight) {
        DEBUG_KEYBOARD("  same (%f) -- bailing", _lastKnownKeyboardHeight);
        return NO; // No animation started
    }

    _lastKnownKeyboardHeight = avoidedBottomHeight;

    NSDictionary *userInfo = [note userInfo];

    _lastAnimationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    _lastAnimationCurve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];

    [self _accessoryToolbarViewFrameNeedsUpdate];

    if (isDid) {
        DEBUG_KEYBOARD("posting frame-did-change");
        _postNotification(self, OUIKeyboardNotifierKeyboardDidChangeFrameNotification, userInfo);
    } else {
        DEBUG_KEYBOARD("posting frame-will-change");
        _postNotification(self, OUIKeyboardNotifierKeyboardWillChangeFrameNotification, userInfo);
    }
    
    return YES;
}

static CGFloat _bottomHeightToAvoidForKeyboardFrameValue(OUIKeyboardNotifier *self, NSValue *keyboardFrameValue)
{
    if (keyboardFrameValue == nil) {
        return 0;
    }

    CGRect keyboardFrame = [keyboardFrameValue CGRectValue];
    DEBUG_KEYBOARD("keyboardFrame: %@", NSStringFromCGRect(keyboardFrame));

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    DEBUG_KEYBOARD("screenBounds: %@", NSStringFromCGRect(screenBounds));
    
    CGFloat keyboardHeight = CGRectGetHeight(keyboardFrame);

    OB_UNUSED_VALUE(keyboardHeight);
    DEBUG_KEYBOARD("keyboardHeight: %f", keyboardHeight);

    CGFloat heightToAvoid = 0;
    CGRect intersectionRect = CGRectIntersection(screenBounds, keyboardFrame);
    if (!CGRectIsNull(intersectionRect)) {
        heightToAvoid = CGRectGetHeight(intersectionRect);
        
        // maxY of the keyboard frame is maxY of its host window, which may not be equal to maxY of superview. We have to assume that the frame of the keyboard view's window is equal to superview.frame
        UIView *accessoryToolbarView = self.accessoryToolbarView;
        UIView *superview = accessoryToolbarView.superview;
        CGRect convertedFrame = [superview.window convertRect:superview.frame toView:superview];
        heightToAvoid -= CGRectGetMaxY(superview.window.frame) - CGRectGetMaxY(convertedFrame);
    }
    DEBUG_KEYBOARD("heightToAvoid: %f", heightToAvoid);
    
    return heightToAvoid;
}

static CGFloat _bottomHeightToAvoidForBeginningKeyboardFrame(OUIKeyboardNotifier *self, NSDictionary *userInfo)
{
    return _bottomHeightToAvoidForKeyboardFrameValue(self, [userInfo objectForKey:UIKeyboardFrameBeginUserInfoKey]);
}

static CGFloat _bottomHeightToAvoidForEndingKeyboardFrame(OUIKeyboardNotifier *self, NSDictionary *userInfo)
{
    return _bottomHeightToAvoidForKeyboardFrameValue(self, [userInfo objectForKey:UIKeyboardFrameEndUserInfoKey]);
}

- (void)_accessoryToolbarViewFrameNeedsUpdate;
{
    _needsUpdate = YES;
    OFAfterDelayPerformBlock(0.0, ^{
        _updateAccessoryToolbarViewFrame(self);
    });
}

static CGRect _targetFrameForHeight(UIView *superview, UIView *accessoryToolbarView, CGFloat height)
{
    CGRect newFrame = accessoryToolbarView.frame;
    if (height > 0) {
        newFrame.origin.x = 0;
        newFrame.origin.y = superview.frame.size.height - accessoryToolbarView.frame.size.height - height;
    } else {
        newFrame.origin.x = 0;
        newFrame.origin.y = superview.frame.size.height - accessoryToolbarView.frame.size.height - superview.safeAreaInsets.bottom;
    }
    return newFrame;
}

static void _updateAccessoryToolbarViewFrame(OUIKeyboardNotifier *self)
{
    self->_needsUpdate = NO;

    UIView *accessoryToolbarView = self.accessoryToolbarView;
    if (accessoryToolbarView == nil) {
        return;
    }

    NSDictionary *userInfo = self->_lastKnownKeyboardInfo;
    CGFloat endHeight = _bottomHeightToAvoidForEndingKeyboardFrame(self, userInfo);

    UIView *superview = accessoryToolbarView.superview;
    CGRect endFrame = _targetFrameForHeight(superview, accessoryToolbarView, endHeight);
    DEBUG_KEYBOARD("accessory: current frame %@, new frame %@", NSStringFromCGRect(self.accessoryToolbarView.frame), NSStringFromCGRect(endFrame));

    if (CGRectEqualToRect(accessoryToolbarView.frame, endFrame)) {
        return; // We're already where we want to be
    }

    NSNumber *durationNumber = [userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey];
    NSNumber *curveNumber = [userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey];

    if (durationNumber == nil || curveNumber == nil) {
        OBASSERT(durationNumber == nil);
        OBASSERT(curveNumber == nil);
        durationNumber = [NSNumber numberWithDouble:0.25];
        curveNumber = [NSNumber numberWithInt:UIViewAnimationCurveEaseInOut];
    }

    [UIView performWithoutAnimation:^{
        CGFloat startHeight = _bottomHeightToAvoidForBeginningKeyboardFrame(self, userInfo);
        CGRect startFrame = _targetFrameForHeight(superview, accessoryToolbarView, startHeight);
        accessoryToolbarView.frame = startFrame;
    }];
    [UIView animateWithDuration:[durationNumber doubleValue] delay:0 options: OUIAnimationOptionFromCurve([curveNumber intValue]) | UIViewAnimationOptionBeginFromCurrentState animations:^{
        accessoryToolbarView.frame = endFrame;
    } completion:nil];
}

@end
