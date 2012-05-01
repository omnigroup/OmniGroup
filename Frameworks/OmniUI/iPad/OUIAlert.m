// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAlert.h>

RCS_ID("$Id$");

/*
 A block-based wrapper for UIAlertView. This is not a subclass, but rather contains a UIAlertView and acts as its delegate. One reason for this is that UIAlertView will call the delegate's -alertViewCancel: when the Home button is pressed, but it won't call its own dismiss method.
 */

@interface OUIAlert () <UIAlertViewDelegate>
#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
#endif
@end

@implementation OUIAlert
{
    UIAlertView *_alertView;
    NSMutableArray *_actions;
    BOOL _shouldCancelWhenApplicationEntersBackground;
    BOOL _hasExtraRetain;
}

- (id)initWithTitle:(NSString *)title message:(NSString *)message cancelButtonTitle:(NSString *)cancelButtonTitle cancelAction:(void (^)(void))cancelAction;
{
    if (!(self = [super init]))
        return nil;

    _alertView = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:cancelButtonTitle otherButtonTitles:nil];
    _alertView.delegate = self;
    
    // The initializer calls -addButtonWithTitle:
    OBASSERT([_alertView numberOfButtons] == 1);

    if (cancelButtonTitle && !cancelAction) 
        cancelAction = ^{}; // Keep our invariants happy.
    
    cancelAction = [cancelAction copy];
    _actions = [[NSMutableArray alloc] initWithObjects:cancelAction, nil];
    [cancelAction release];
    
    // This is NOT the default for UIAlertView as of 4.0.
    _shouldCancelWhenApplicationEntersBackground = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];

    OBINVARIANT([self _checkInvariants]);
    return self;
}

- (void)dealloc;
{
    if (_shouldCancelWhenApplicationEntersBackground)
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];

    _alertView.delegate = nil;
    [_alertView release];
    [_actions release];
    
    [super dealloc];
}

@synthesize shouldCancelWhenApplicationEntersBackground = _shouldCancelWhenApplicationEntersBackground;
- (void)setShouldCancelWhenApplicationEntersBackground:(BOOL)shouldCancelWhenApplicationEntersBackground;
{
    if (_shouldCancelWhenApplicationEntersBackground == shouldCancelWhenApplicationEntersBackground)
        return;
    
    _shouldCancelWhenApplicationEntersBackground = shouldCancelWhenApplicationEntersBackground;
    
    if (_shouldCancelWhenApplicationEntersBackground)
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    else
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)addButtonWithTitle:(NSString *)title action:(void (^)(void))action;
{
    OBINVARIANT([self _checkInvariants]);
    
    NSInteger buttonIndex = [_alertView addButtonWithTitle:title];
    OB_UNUSED_VALUE(buttonIndex);
    OBASSERT(buttonIndex == (NSInteger)[_actions count]);

    action = [action copy];
    [_actions addObject:action];
    [action release];

    OBINVARIANT([self _checkInvariants]);
}

- (void)show;
{
    OBPRECONDITION(_alertView.visible == NO);
    OBPRECONDITION(_alertView); // We clear this on first cancel
    
    // We want to live as long as the alert is on screen!
    if (!_hasExtraRetain) {
        _hasExtraRetain = YES;
        CFRetain(self);
    }
    
    [_alertView show];
}

- (void)cancelAnimated:(BOOL)animated;
{
    [self dismissWithClickedButtonIndex:0 animated:animated];
}

- (void)dismissWithClickedButtonIndex:(NSInteger)buttonIndex animated:(BOOL)animated;
{
    OBPRECONDITION(_alertView.visible == YES);
    OBPRECONDITION(_alertView); // We clear this on first cancel
    
    [_alertView dismissWithClickedButtonIndex:buttonIndex animated:animated];
    [self _invokeActionForButtonIndex:buttonIndex];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex;
{
    [self _invokeActionForButtonIndex:buttonIndex];
}

- (void)alertViewCancel:(UIAlertView *)alertView;
{
    // Docs say, "In iOS 4.0 and later, alert views are not dismissed automatically when an application moves to the background.". Unclear when the system will call this automatically, if ever (incoming call or text, maybe?)
    [self alertView:alertView clickedButtonAtIndex:0];
}

#pragma mark - Private

- (void)_invokeActionForButtonIndex:(NSUInteger)buttonIndex;
{
    OBINVARIANT([self _checkInvariants]);
    
    void (^action)(void) = [[[_actions objectAtIndex:buttonIndex] retain] autorelease];
    
    // break retain cycles, possibly
    [_actions release];
    _actions = nil;
    
    [_alertView release];
    _alertView = nil;
    
    action();
    
    if (_hasExtraRetain) {
        _hasExtraRetain = NO; // Do this first in case this causes us to be deallocated...
        CFRelease(self);
    }
}

- (void)_applicationDidEnterBackground:(NSNotification *)note;
{
    // The visible property unhelpfully returns NO when the app is in the background.
    if (_alertView.window == nil)
        return; // -show never called?
    
    [self dismissWithClickedButtonIndex:0 animated:NO];
}

#pragma mark - Debugging

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
{
    OBINVARIANT([_alertView numberOfButtons] == (NSInteger)[_actions count]);
    OBINVARIANT([_alertView cancelButtonIndex] == 0);
    return YES;
}
#endif

@end
