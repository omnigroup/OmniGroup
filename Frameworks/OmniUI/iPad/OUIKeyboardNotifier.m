// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniUI/OUIKeyboardNotifier.h>

#import <OmniFoundation/OFExtent.h>

#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
#define DEBUG_KEYBOARD(format, ...) NSLog(@"KEYBOARD: " format, ## __VA_ARGS__)
#else
#define DEBUG_KEYBOARD(format, ...)
#endif

@interface OUIKeyboardNotifier ()

@end

@implementation OUIKeyboardNotifier

NSString * const OUIKeyboardNotifierKeyboardWillChangeFrameNotification = @"OUIKeyboardNotifierKeyboardWillChangeFrameNotification";
NSString * const OUIKeyboardNotifierKeyboardDidChangeFrameNotification = @"OUIKeyboardNotifierKeyboardDidChangeFrameNotification";
NSString * const OUIKeyboardNotifierOriginalUserInfoKey = @"OUIKeyboardNotifierOriginalUserInfoKey";
NSString * const OUIKeyboardNotifierLastKnownKeyboardHeightKey = @"OUIKeyboardNotifierLastKnownKeyboardHeightKey";

+ (instancetype)sharedNotifier;
{
    static OUIKeyboardNotifier *sharedNotifier;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedNotifier = [[OUIKeyboardNotifier alloc] init];
    });
    
    return sharedNotifier;
}

- (id)init
{
    if (!(self = [super init]))
        return nil;

    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    [defaultCenter addObserver:self selector:@selector(_keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(_keyboardDidChangeFrame:) name:UIKeyboardDidChangeFrameNotification object:nil];

    // We can't depend on the keyboard change notification happening before events like UIControlEventEditingDidBegin firing. So, we have a default value here that might be wrong on the first animation.
    _lastAnimationDuration = 0.25;
    _lastAnimationCurve = 7; // Doesn't match any entry in UIViewAnimationCurve ... ><
    
    return self;
}

- (BOOL)isKeyboardVisible;
{
    return _lastKnownKeyboardHeight > 0;
}

- (void)setAccessoryToolbarView:(UIView *)accessoryToolbarView;
{
    if (_accessoryToolbarView == accessoryToolbarView)
        return;
    
    _accessoryToolbarView = accessoryToolbarView;
    _updateAccessoryToolbarViewFrame(self, nil);
}

#pragma mark - Private

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
    NSDictionary *userInfo = @{ OUIKeyboardNotifierOriginalUserInfoKey : originalInfo, OUIKeyboardNotifierLastKnownKeyboardHeightKey : @(self.lastKnownKeyboardHeight) };
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:self userInfo:userInfo];
}

- (BOOL)_handleKeyboardFrameChange:(NSNotification *)note isDid:(BOOL)isDid;
{
    CGFloat avoidedBottomHeight = _bottomHeightToAvoidForEndingKeyboardFrame(self, note);
    if (_lastKnownKeyboardHeight == avoidedBottomHeight) {
        DEBUG_KEYBOARD("  same (%f) -- bailing", _lastKnownKeyboardHeight);
        return NO; // No animation started
    }
    
    _lastKnownKeyboardHeight = avoidedBottomHeight;

    NSDictionary *userInfo = [note userInfo];

    _lastAnimationDuration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    _lastAnimationCurve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];
    OBASSERT((long)_lastAnimationCurve == 7, "Did UIKit start using a standard or yet another different private animation curve?");
    
    _updateAccessoryToolbarViewFrame(self, userInfo);
    if (isDid) {
        DEBUG_KEYBOARD("posting frame-did-change");
        _postNotification(self, OUIKeyboardNotifierKeyboardDidChangeFrameNotification, userInfo);
    }
    else {
        DEBUG_KEYBOARD("posting frame-will-change");
        _postNotification(self, OUIKeyboardNotifierKeyboardWillChangeFrameNotification, userInfo);
    }
    
    return YES;
}

static CGFloat _bottomHeightToAvoidForEndingKeyboardFrame(OUIKeyboardNotifier *self, NSNotification *note)
{
    NSValue *keyboardEndFrameValue = [[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey];
    if (!keyboardEndFrameValue) {
        return 0;
    }
    CGRect keyboardEndFrame = [keyboardEndFrameValue CGRectValue];
    DEBUG_KEYBOARD("keyboardEndFrame: %@", NSStringFromCGRect(keyboardEndFrame));

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    DEBUG_KEYBOARD("screenBounds: %@", NSStringFromCGRect(screenBounds));
    
    CGFloat keyboardHeight = keyboardEndFrame.size.height;
    BOOL isDocked = (screenBounds.size.height - keyboardEndFrame.size.height) == keyboardEndFrame.origin.y;
    
    DEBUG_KEYBOARD("keyboardHeight: %f", keyboardHeight);
    DEBUG_KEYBOARD("isDocked: %@", isDocked ? @"YES" : @"NO");

    CGFloat heightToAvoid = (isDocked) ? keyboardHeight : 0;
    DEBUG_KEYBOARD("heightToAvoid: %f", heightToAvoid);
    
    return heightToAvoid;
}

static void _updateAccessoryToolbarViewFrame(OUIKeyboardNotifier *self, NSDictionary *userInfo)
{
    if (!self.accessoryToolbarView) {
        return;
    }

    UIView *superview = self.accessoryToolbarView.superview;
    CGRect newFrame = self.accessoryToolbarView.frame;
    if (self.lastKnownKeyboardHeight > 0) {
        newFrame.origin.x = 0;
        newFrame.origin.y = superview.frame.size.height - self.accessoryToolbarView.frame.size.height - self.lastKnownKeyboardHeight;
    }
    else {
        newFrame.origin.x = 0;
        newFrame.origin.y = superview.frame.size.height - self.accessoryToolbarView.frame.size.height;
    }

    DEBUG_KEYBOARD("accessory: current frame %@, new frame %@", NSStringFromCGRect(self.accessoryToolbarView.frame), NSStringFromCGRect(newFrame));

    if (CGRectEqualToRect(self.accessoryToolbarView.frame, newFrame)) {
        return;
    }

    NSNumber *durationNumber = [userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey];
    NSNumber *curveNumber = [userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey];

    if (!durationNumber || !curveNumber) {
        OBASSERT((durationNumber == nil) == (curveNumber == nil));
        durationNumber = [NSNumber numberWithDouble:0.25];
        curveNumber = [NSNumber numberWithInt:UIViewAnimationCurveEaseInOut];
    }

    [UIView animateWithDuration:[durationNumber doubleValue] animations:^{
        [UIView setAnimationCurve:[curveNumber intValue]];
        [UIView setAnimationBeginsFromCurrentState:YES];
        self.accessoryToolbarView.frame = newFrame;
    }];
}

@end
