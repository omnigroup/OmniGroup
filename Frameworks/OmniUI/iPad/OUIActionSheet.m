// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIActionSheet.h>

RCS_ID("$Id$");

NSString * const OUIActionSheetDidDismissNotification = @"OUIActionSheetDidDismissNotification";

@interface OUIActionSheet (/* Private */)

- (void)_addAction:(void(^)(void))action;

@end

@implementation OUIActionSheet
{
    NSMutableArray *_actions;
    NSString *_identifier;
}

- (id)initWithIdentifier:(NSString *)identifier;
{
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
    }
    return self;
}

- (void)setDelegate:(id<UIActionSheetDelegate>)delegate
{
    if (!delegate) {
        // [super dealloc] trys to set the delegate to nil. If that's what's going on, just let it go.
        return;
    }
    OBRejectUnusedImplementation(self, _cmd);
}

- (void)dealloc;
{
    [_identifier release];
    [_actions release];
    
    [super dealloc];
}

#pragma mark -
#pragma mark Public

- (NSString *)identifier;
{
    return _identifier;
}

- (void)addButtonWithTitle:(NSString *)buttonTitle forAction:(void(^)(void))action;
{    
    OBPRECONDITION(buttonTitle);
    OBPRECONDITION(action);
    
    [self addButtonWithTitle:buttonTitle];
    [self _addAction:action];
}

- (void)setDestructiveButtonTitle:(NSString *)destructiveButtonTitle andAction:(void(^)(void))action;
{
    OBPRECONDITION(destructiveButtonTitle);
    OBPRECONDITION(action);
    
    self.destructiveButtonIndex = [self addButtonWithTitle:destructiveButtonTitle];
    [self _addAction:action];
}

- (void)setCancelButtonTitle:(NSString *)cancelButtonTitle andAction:(void(^)(void))action;
{
    OBPRECONDITION(cancelButtonTitle);
    OBPRECONDITION(action);
    
    self.cancelButtonIndex = [self addButtonWithTitle:cancelButtonTitle];
    [self _addAction:action];
}

#pragma mark -
#pragma mark Private

- (void)_addAction:(void(^)(void))action;
{
    OBPRECONDITION(action);
    
    if (!_actions) {
        _actions = [[NSMutableArray alloc] init];
    }
    
    action = [action copy];
    [_actions addObject:action];
    [action release];
}


#pragma mark -
#pragma mark UIActionSheet

- (void)dismissWithClickedButtonIndex:(NSInteger)buttonIndex animated:(BOOL)animated;
{
    [super dismissWithClickedButtonIndex:buttonIndex animated:animated];
    
    // -1 means cancel (clicked out) if you don't have a cancel item
    if (buttonIndex >= 0 && buttonIndex != [self cancelButtonIndex]) {
        void (^action)(void) = (typeof(action))[_actions objectAtIndex:buttonIndex];
        if (action) {
            action();
        }
    }
    
    [_actions release];
    _actions = nil;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIActionSheetDidDismissNotification object:self];
}

@end
