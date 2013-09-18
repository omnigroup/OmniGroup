// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIUndoButtonController.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIUndoButton.h>
#import <OmniUI/OUIMenuController.h>

RCS_ID("$Id$");

@interface OUIUndoButtonController () <OUIMenuControllerDelegate>
@end

@implementation OUIUndoButtonController
{
    OUIMenuController *_menuController;
}

@synthesize undoBarButtonItemTarget = _weak_undoBarButtonItemTarget;

- (void)showUndoMenuFromItem:(OUIUndoBarButtonItem *)item;
{
    if (_menuController.visible)
        return;

    if (!_menuController)
        _menuController = [[OUIMenuController alloc] initWithDelegate:self];
    
    _menuController.tintColor = _tintColor;
    _menuController.sizesToOptionWidth = YES;
    _menuController.textAlignment = NSTextAlignmentCenter;
    _menuController.showsDividersBetweenOptions = NO;
    _menuController.padTopAndBottom = YES;
    
    // We will provide exactly the same number/title options but possibly w/o an action.
    _menuController.optionInvocationAction = OUIMenuControllerOptionInvocationActionReload;
    
    // TODO: Add support to OUIMenuController to not dismiss when an action is taken, but to instead ask for actions again.
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIUndoPopoverWillShowNotification object:self];
    [_menuController showMenuFromSender:item];
}

- (BOOL)dismissUndoMenu;
{
    if (!_menuController.visible)
        return NO;
    [_menuController dismissMenuAnimated:YES];
    return YES;
}

- (BOOL)isMenuVisible;
{
    return _menuController.visible;
}

#pragma mark - Private

- (NSArray *)menuControllerOptions:(OUIMenuController *)menu;
{
    id <OUIUndoBarButtonItemTarget> target = _weak_undoBarButtonItemTarget;
    
    NSMutableArray *options = [NSMutableArray array];
    
    OUIMenuOptionAction undoAction;
    if ([target canPerformAction:@selector(undo:) withSender:nil]) {
        undoAction = [^{
            if (target)
                [target undo:nil];
        } copy];
    }
    [options addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Undo", @"OmniUI", OMNI_BUNDLE, @"Undo button title") action:undoAction]];
    
    OUIMenuOptionAction redoAction;
    if ([target canPerformAction:@selector(redo:) withSender:nil]) {
        redoAction = [^{
            if (target)
                [target redo:nil];
        } copy];
    }
    [options addObject:[OUIMenuOption optionWithTitle:NSLocalizedStringFromTableInBundle(@"Redo", @"OmniUI", OMNI_BUNDLE, @"Redo button title") action:redoAction]];
    
    return options;
}

@end
