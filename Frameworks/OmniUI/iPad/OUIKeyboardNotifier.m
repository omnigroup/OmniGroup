// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

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

@interface OUIKeyboardNotifier ()

@property (nonatomic, nullable, copy) NSDictionary *lastKnownKeyboardInfo;

@end

#pragma mark -

typedef OFWeakReference <UIView *> *ViewReference;

@implementation OUIKeyboardNotifier
{
    NSMutableArray <ViewReference> *_accessoryViews;
    CGFloat _lastKnownKeyboardHeight;
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

    _accessoryViews = [[NSMutableArray alloc] init];

    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];

    [defaultCenter addObserver:self selector:@selector(_keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(_keyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(_keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(_keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    
    [defaultCenter addObserver:self selector:@selector(_keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(_keyboardDidChangeFrame:) name:UIKeyboardDidChangeFrameNotification object:nil];

    [defaultCenter addObserver:self selector:@selector(_sceneWillDeactivate:) name:UISceneWillDeactivateNotification object:nil];

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

- (OUIKeyboardState)keyboardState;
{
    return _keyboardState;
}

- (CGFloat)lastKnownKeyboardHeight;
{
    return _lastKnownKeyboardHeight;
}

- (nullable NSDictionary *)lastKnownKeyboardInfo;
{
    return _lastKnownKeyboardInfo;
}

- (void)addAccessoryToolbarView:(UIView *)view;
{
    OBPRECONDITION(view);
    [OFWeakReference add:view toReferences:_accessoryViews];
    _updateAccessoryToolbarViewFrames(self);
}

- (void)removeAccessoryToolbarView:(UIView *)view;
{
    OBPRECONDITION(view);
    [OFWeakReference remove:view fromReferences:_accessoryViews];
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

- (UIViewAnimationOptions)animationOptionsForLastKnownAnimationCurve
{
    return OUIAnimationOptionFromCurve(self.lastAnimationCurve);
}

#pragma mark - Private

- (void)_sceneWillDeactivate:(NSNotification *)note;
{
    if (_shouldPreserveLastKeyboardStateWhenSceneDeactivates)
        return;

    self.keyboardState = OUIKeyboardStateHidden;
    _lastKnownKeyboardHeight = 0;
    _lastKnownKeyboardInfo = nil;
}

- (void)_keyboardWillShow:(NSNotification *)note;
{
    self.keyboardState = OUIKeyboardStateAppearing;
    DEBUG_KEYBOARD("keyboard visibility state is now «appearing»");
    
    NSDictionary *userInfo = [note userInfo];
    _postNotification(self, OUIKeyboardNotifierKeyboardWillShowNotification, userInfo);
}

- (void)_keyboardDidShow:(NSNotification *)note;
{
    self.keyboardState = OUIKeyboardStateVisible;
    DEBUG_KEYBOARD("keyboard visibility state is now «visible»");

    NSDictionary *userInfo = [note userInfo];
    _postNotification(self, OUIKeyboardNotifierKeyboardDidShowNotification, userInfo);
}

- (void)_keyboardWillHide:(NSNotification *)note;
{
    self.keyboardState = OUIKeyboardStateDisappearing;
    DEBUG_KEYBOARD("keyboard visibility state is now «disappearing»");
    
    NSDictionary *userInfo = [note userInfo];
    _postNotification(self, OUIKeyboardNotifierKeyboardWillHideNotification, userInfo);
}

- (void)_keyboardDidHide:(NSNotification *)note;
{
    self.keyboardState = OUIKeyboardStateHidden;
    DEBUG_KEYBOARD("keyboard visibility state is now «hidden»");
    
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

    // We used to have at most one accessory view, but on iPad we could have multiple documents open. We may need to restructure this if the heights end up actually being different.
    __block CGFloat avoidedBottomHeight = 0.0;
    if (![OFWeakReference forEachReference:_accessoryViews perform:^(UIView *accessoryToolbarView) {
        avoidedBottomHeight = MAX(avoidedBottomHeight, _bottomHeightToAvoidForEndingKeyboardFrame(self, _lastKnownKeyboardInfo, accessoryToolbarView));
    }]) {
        avoidedBottomHeight = _bottomHeightToAvoidForEndingKeyboardFrame(self, _lastKnownKeyboardInfo, nil);
    }
    
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
        DEBUG_KEYBOARD("posting frame-did-change, height %f", _lastKnownKeyboardHeight);
        _postNotification(self, OUIKeyboardNotifierKeyboardDidChangeFrameNotification, userInfo);
    } else {
        DEBUG_KEYBOARD("posting frame-will-change, height %f", _lastKnownKeyboardHeight);
        _postNotification(self, OUIKeyboardNotifierKeyboardWillChangeFrameNotification, userInfo);
    }
    
    return YES;
}

static CGFloat _bottomHeightToAvoidForKeyboardFrameValue(OUIKeyboardNotifier *self, NSValue *keyboardFrameValue, UIView * _Nullable accessoryToolbarView)
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
        
        if (accessoryToolbarView != nil) {
            // maxY of the keyboard frame is maxY of its host window, which may not be equal to maxY of superview. We have to assume that the frame of the keyboard view's window is equal to superview.frame
            UIView *superview = accessoryToolbarView.superview;
            CGRect convertedFrame = [superview.window convertRect:superview.frame toView:superview];
            heightToAvoid -= CGRectGetMaxY(superview.window.frame) - CGRectGetMaxY(convertedFrame);
        }
    }
    DEBUG_KEYBOARD("heightToAvoid: %f", heightToAvoid);
    
    return heightToAvoid;
}

static CGFloat _bottomHeightToAvoidForBeginningKeyboardFrame(OUIKeyboardNotifier *self, NSDictionary *userInfo, UIView *accessoryToolbarView)
{
    return _bottomHeightToAvoidForKeyboardFrameValue(self, [userInfo objectForKey:UIKeyboardFrameBeginUserInfoKey], accessoryToolbarView);
}

static CGFloat _bottomHeightToAvoidForEndingKeyboardFrame(OUIKeyboardNotifier *self, NSDictionary *userInfo, UIView * _Nullable accessoryToolbarView)
{
    NSValue *beginFrameValue = userInfo[UIKeyboardFrameBeginUserInfoKey];
    NSValue *endFrameValue = userInfo[UIKeyboardFrameEndUserInfoKey];
    if (beginFrameValue != nil && endFrameValue != nil) {
        // If the keyboard frame does not touch at the bottom of the screen, then it's floating, and we don't need to avoid any height.
        // Note that we will get "animations" when switching text input focus while there already is a focus and the keyboard will be fully on screen with the bottom touching the edge of the screen.
        // Note *also* that we need to check the beginning and ending frame (otherwise we will end up avoiding zero height when the keyboard transitions from floating to non-floating).
        CGRect beginFrame = beginFrameValue.CGRectValue;
        CGRect endFrame = endFrameValue.CGRectValue;
        CGRect screenBounds = UIScreen.mainScreen.bounds;

        if (CGRectGetMinY(beginFrame) != CGRectGetMaxY(screenBounds) &&
            CGRectGetMaxY(beginFrame) != CGRectGetMaxY(screenBounds) &&
            CGRectGetMinY(endFrame) != CGRectGetMaxY(screenBounds) &&
            CGRectGetMaxY(endFrame) != CGRectGetMaxY(screenBounds)) {
            return 0;
        }
    } else {
        // No entry in the dictionary
        return 0;
    }
    
    return _bottomHeightToAvoidForKeyboardFrameValue(self, endFrameValue, accessoryToolbarView);
}

- (void)_accessoryToolbarViewFrameNeedsUpdate;
{
    _updateAccessoryToolbarViewFrames(self);
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

static void _updateAccessoryToolbarViewFrames(OUIKeyboardNotifier *self)
{
    [OFWeakReference forEachReference:self->_accessoryViews perform:^(UIView *view) {
        _updateAccessoryToolbarViewFrame(self, view);
    }];
}

static void _updateAccessoryToolbarViewFrame(OUIKeyboardNotifier *self, UIView *accessoryToolbarView)
{
    NSDictionary *userInfo = self->_lastKnownKeyboardInfo;
    CGFloat endHeight = _bottomHeightToAvoidForEndingKeyboardFrame(self, userInfo, accessoryToolbarView);

    UIView *superview = accessoryToolbarView.superview;
    CGRect endFrame = _targetFrameForHeight(superview, accessoryToolbarView, endHeight);
    DEBUG_KEYBOARD("accessory: current frame %@, new frame %@", NSStringFromCGRect(accessoryToolbarView.frame), NSStringFromCGRect(endFrame));

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
        CGFloat startHeight = _bottomHeightToAvoidForBeginningKeyboardFrame(self, userInfo, accessoryToolbarView);
        CGRect startFrame = _targetFrameForHeight(superview, accessoryToolbarView, startHeight);
        accessoryToolbarView.frame = startFrame;
    }];
    [UIView animateWithDuration:[durationNumber doubleValue] delay:0 options: OUIAnimationOptionFromCurve([curveNumber intValue]) | UIViewAnimationOptionBeginFromCurrentState animations:^{
        accessoryToolbarView.frame = endFrame;
    } completion:nil];
}

@end

NS_ASSUME_NONNULL_END

