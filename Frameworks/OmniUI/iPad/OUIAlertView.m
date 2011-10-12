// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAlertView.h>

RCS_ID("$Id$");

@interface OUIAlertView ()
#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
#endif
@end

@implementation OUIAlertView
{
    NSMutableArray *_actions;
}

- (id)initWithTitle:(NSString *)title message:(NSString *)message cancelButtonTitle:(NSString *)cancelButtonTitle cancelAction:(void (^)(void))cancelAction;
{
    if (!(self = [super initWithTitle:title message:message delegate:nil cancelButtonTitle:cancelButtonTitle otherButtonTitles:nil]))
        return nil;

    // The initializer calls -addButtonWithTitle:
    OBASSERT([self numberOfButtons] == 1);
    
    cancelAction = [cancelAction copy];
    _actions = [[NSMutableArray alloc] initWithObjects:cancelAction, nil];
    [cancelAction release];
    
    OBINVARIANT([self _checkInvariants]);
    return self;
}

- (void)dealloc;
{
    [_actions release];
    [super dealloc];
}

- (void)addButtonWithTitle:(NSString *)title action:(void (^)(void))action;
{
    OBINVARIANT([self _checkInvariants]);
    
    NSInteger buttonIndex = [super addButtonWithTitle:title];
    OB_UNUSED_VALUE(buttonIndex);
    OBASSERT(buttonIndex == (NSInteger)[_actions count]);

    action = [action copy];
    [_actions addObject:action];
    [action release];

    OBINVARIANT([self _checkInvariants]);
}

#pragma mark -
#pragma mark UIAlertView subclass

- (void)dismissWithClickedButtonIndex:(NSInteger)buttonIndex animated:(BOOL)animated;
{
    OBINVARIANT([self _checkInvariants]);

    void (^action)(void) = [[[_actions objectAtIndex:buttonIndex] retain] autorelease];
    
    // break retain cycles, possibly
    [_actions release];
    _actions = nil;
    
    [super dismissWithClickedButtonIndex:buttonIndex animated:animated];

    action();
}

#pragma mark -
#pragma mark Debugging

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
{
    OBINVARIANT([self numberOfButtons] == (NSInteger)[_actions count]);
    OBINVARIANT([self cancelButtonIndex] == 0);
    return YES;
}
#endif

@end
