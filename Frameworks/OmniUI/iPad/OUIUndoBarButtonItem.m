// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIUndoBarButtonItem.h>

@import OmniAppKit.OAStrings; // For OACancel()

#import <OmniUI/NSUndoManager-OUIExtensions.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIUndoButton.h>
#import <OmniUI/UIPopoverPresentationController-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUIMenuController.h>
#import "OUIParameters.h"

// OUIUndoBarButtonItemTarget
OBDEPRECATED_METHOD(-undoBarButtonItemWillShowPopover); // Use the OUIAppController single-popover helper instead.

static NSString * const OUIUndoBarButtonItemUpdateStateNotification = @"OUIUndoBarButtonItemUpdateStateNotification";
static NSString * const OUIUndoBarButtonItemDismissMenuNotification = @"OUIUndoBarButtonItemDismissMenuNotification";
NSString * const OUIUndoPopoverWillShowNotification = @"OUIUndoPopoverWillShowNotification";

// We don't implement this, but UIBarButtonItem doesn't declare that is does (though it really does). If UIBarButtonItem doesn't implement coder later, then our subclass method will never get called and we'll never fail on the call to super.
@interface UIBarButtonItem (NSCoding) <NSCoding>
@end

@interface OUIUndoBarButtonItem ()
- (OUIMenuController *)_menuControllerForRegularMenuPresentationInWindow:(UIWindow *)window;
- (UIAlertController *)_alertControllerForCompactMenuPresentation;
@end

@implementation OUIUndoBarButtonItem
{
    OUIUndoButton *_undoButton;
    OUIMenuController *_menuController;

    UITapGestureRecognizer *_tapRecognizer;
    UILongPressGestureRecognizer *_longPressRecognizer;

    __weak id <OUIUndoBarButtonItemTarget>  _weak_undoBarButtonItemTarget;
    
    BOOL _canUndo, _canRedo;
    NSInteger _tempDisabledCount;
}

- (id)initWithImage:(UIImage *)image style:(UIBarButtonItemStyle)style target:(id)target action:(SEL)action;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (id)initWithTitle:(NSString *)title style:(UIBarButtonItemStyle)style target:(id)target action:(SEL)action;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (id)initWithBarButtonSystemItem:(UIBarButtonSystemItem)systemItem target:(id)target action:(SEL)action;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (id)initWithCustomView:(UIView *)customView;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

static id _commonInit(OUIUndoBarButtonItem *self)
{
    self->_tempDisabledCount = 0;
    self->_undoButton = [OUIUndoButton buttonWithType:UIButtonTypeSystem];
    self->_undoButton.contentMode = UIViewContentModeCenter;

    [self->_undoButton sizeToFit];
    self.customView = self->_undoButton;

    // adjust the text label because UIButton and UITitleBarButton place their labels 1 apple point off from each other by default.
    [self->_undoButton setTitleEdgeInsets:UIEdgeInsetsMake(0,0,-2,0)];

    [self->_undoButton addTarget:self action:@selector(_touchDown:) forControlEvents:UIControlEventTouchDown];

    self->_tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_undoButtonTap:)];
    [self->_undoButton addGestureRecognizer:self->_tapRecognizer];

    self->_longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_undoButtonPressAndHold:)];
    [self->_undoButton addGestureRecognizer:self->_longPressRecognizer];

    [self->_undoButton.titleLabel setFont:[UIFont systemFontOfSize:17]];
    [self->_undoButton sizeToFit];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_updateNotification:) name:NSUndoManagerDidUndoChangeNotification object:nil];
    [center addObserver:self selector:@selector(_updateNotification:) name:NSUndoManagerDidRedoChangeNotification object:nil];
    [center addObserver:self selector:@selector(_updateNotification:) name:NSUndoManagerWillCloseUndoGroupNotification object:nil];
    [center addObserver:self selector:@selector(_updateNotification:) name:OUIUndoManagerDidRemoveAllActionsNotification object:nil];
    [center addObserver:self selector:@selector(_updateNotification:) name:OUIUndoBarButtonItemUpdateStateNotification object:nil];
    
    [center addObserver:self selector:@selector(_reallyDismissUndoMenu:) name:OUIUndoBarButtonItemDismissMenuNotification object:nil];

    return self;
}

- (void)_updateNotification:(NSNotification *)notification;
{
    OBASSERT([NSThread isMainThread], "All undo operations should be on the main thread since NSUndoManager schedules end-of-event operations in the runloop.");
    
    [self _updateState];
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- init;
{
    if (!(self = [super init]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc;
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    
    [center removeObserver:self name:NSUndoManagerDidUndoChangeNotification object:nil];
    [center removeObserver:self name:NSUndoManagerDidRedoChangeNotification object:nil];
    [center removeObserver:self name:NSUndoManagerWillCloseUndoGroupNotification object:nil];
    [center removeObserver:self name:OUIUndoManagerDidRemoveAllActionsNotification object:nil];
    [center removeObserver:self name:OUIUndoBarButtonItemUpdateStateNotification object:nil];

    [center removeObserver:self name:OUIUndoBarButtonItemDismissMenuNotification object:nil];
    
    [_undoButton removeTarget:self action:@selector(_touchDown:) forControlEvents:UIControlEventTouchDown];
    [_undoButton removeGestureRecognizer:_tapRecognizer];
    [_undoButton removeGestureRecognizer:_longPressRecognizer];
}

#pragma mark - API

+ (void)updateState;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIUndoBarButtonItemUpdateStateNotification object:nil];
}

@synthesize undoBarButtonItemTarget = _weak_undoBarButtonItemTarget;
- (void)setUndoBarButtonItemTarget:(id<OUIUndoBarButtonItemTarget>)undoBarButtonItemTarget;
{
    _weak_undoBarButtonItemTarget = undoBarButtonItemTarget;
    
    [self _updateState];
}

@synthesize button = _undoButton;

- (void)setDisabledTemporarily:(BOOL)disabledTemporarily {
    
    if (disabledTemporarily) {
        _tempDisabledCount += 1;
    } else {
        _tempDisabledCount -= 1;
    }
    OBASSERT(_tempDisabledCount >= 0, "Unmatched calls to disableTemporarily");
    
    _disabledTemporarily = _tempDisabledCount > 0;
    [self _updateState];
}

- (void)updateButtonForCompact:(BOOL)isCompact;
{
    if (isCompact) {
        [_undoButton setImage:[UIImage imageNamed:@"OUIToolbarUndo-Compact" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
        [_undoButton setTitle:nil forState:UIControlStateNormal];
    } else {
        if (self.useImageForNonCompact) {
            [_undoButton setImage:[UIImage imageNamed:@"OUIToolbarUndo" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
            [_undoButton setTitle:nil forState:UIControlStateNormal];
        } else {
            [_undoButton setImage:nil forState:UIControlStateNormal];
            [_undoButton setTitle:OUILocalizedStringUndo() forState:UIControlStateNormal];
        }
    }
    
    [_undoButton sizeToFit];
}

#pragma mark - Accessibility
- (NSString *)accessibilityLabel
{
    return OUILocalizedStringUndo();
}

#pragma mark -
#pragma mark Private

- (void)_updateState;
{
    // We just use the undo manager notifications to determine *when* to ask the target whether it can undo/redo. Likely the target will just use -[NSUndoManager can{Undo,Redo}], but in some cases it might have additional restrictions.
    id <OUIUndoBarButtonItemTarget> target = _weak_undoBarButtonItemTarget;
    _canUndo = [target canPerformAction:@selector(undo:) withSender:self];
    _canRedo = [target canPerformAction:@selector(redo:) withSender:self];
        
    BOOL enabled = (!self.disabledTemporarily && (_canUndo || _canRedo));
    
    if (enabled) {
        if (_canUndo) {
            // Tap should undo, press and hold should give menu
            _tapRecognizer.enabled = YES;
            _longPressRecognizer.enabled = YES;
        } else if (_canRedo) {
            // Touch-down should do menu
            _tapRecognizer.enabled = NO;
            _longPressRecognizer.enabled = NO; // our touch-down will do it.
        }
    } else {
        // Nothing
        _tapRecognizer.enabled = NO;
        _longPressRecognizer.enabled = NO;
    }
    
    // Our superclass enabled property sets whether we want to be enabled at all.
    self.enabled = enabled;
    [_undoButton setEnabled:enabled];
}

- (void)_showUndoMenu;
{
    id menuPresenter;
    id undoBarButtonItemTarget = _weak_undoBarButtonItemTarget;
    
    if ([undoBarButtonItemTarget respondsToSelector:@selector(targetForAction:withSender:)]) {
        menuPresenter = [undoBarButtonItemTarget targetForAction:@selector(presentMenuForUndoBarButtonItem:) withSender:self];
    } else {
        menuPresenter = [undoBarButtonItemTarget respondsToSelector:@selector(presentMenuForUndoBarButtonItem:)] ? undoBarButtonItemTarget : nil;
    }
    
    [menuPresenter presentMenuForUndoBarButtonItem:self];
}

- (OUIMenuController *)_menuControllerForRegularMenuPresentationInWindow:(UIWindow *)window NS_EXTENSION_UNAVAILABLE_IOS("");
{
    if (!_menuController) {
        _menuController = [[OUIMenuController alloc] init];
        _menuController.sizesToOptionWidth = YES;
        _menuController.textAlignment = NSTextAlignmentCenter;
        _menuController.showsDividersBetweenOptions = NO;
        
        // We will provide exactly the same number/title options but possibly w/o an action.
        _menuController.optionInvocationAction = OUIMenuControllerOptionInvocationActionReload;

        _menuController.popoverPresentationController.backgroundColor = UIColor.secondarySystemBackgroundColor;
        _menuController.menuBackgroundColor = UIColor.secondarySystemBackgroundColor;
        _menuController.menuOptionBackgroundColor = nil;
        _menuController.menuOptionSelectionColor = nil;
    }
    
    // retint each time, because Focus uses multiple tints
    _menuController.tintColor = window.window.tintColor;
    
    id <OUIUndoBarButtonItemTarget> target = _weak_undoBarButtonItemTarget;
    
    // Build Options
    OUIMenuOption *undoOption = [OUIMenuOption optionWithTitle:OUILocalizedStringUndo()
                                                        action:^(OUIMenuInvocation *invocation){
                                                            if (target) {
                                                                [target undo:nil];
                                                            }
                                                        } validator:^BOOL(OUIMenuOption *option){
                                                            return [target canPerformAction:@selector(undo:) withSender:nil];
                                                        }];
    
    
    OUIMenuOption *redoOption = [OUIMenuOption optionWithTitle:OUILocalizedStringRedo()
                                                        action:^(OUIMenuInvocation *invocation){
                                                            if (target) {
                                                                [target redo:nil];
                                                            }
                                                        } validator:^BOOL(OUIMenuOption *option){
                                                            return [target canPerformAction:@selector(redo:) withSender:nil];
                                                        }];
    
    _menuController.topOptions = @[undoOption, redoOption];
    
    
    // Setup Popover Presentation Controller - This must be done each time becase when the popover is dismissed the current popoverPresentationController is released and a new one is created next time.
    
    // workaround for <bug:///155450> (iOS-OmniPlan Unassigned: Undo popover shifts to the left side of the screen if you bring it up twice)
    // When the bar button item has a custom view and is in a _UIButtonBarStackView, the second time we present a popover from it, the popover is instead presented from the left side of the stack view. In fact if we use the custom view as sourceView and an appropriate sourceRect, we wind up with an equivalent bug. So instead we'll just use the stack view.
    UIStackView *enclosingStackView = OB_CHECKED_CAST_OR_NIL(UIStackView, [_undoButton enclosingViewOfClass:[UIStackView class]]);
    if (enclosingStackView) {
        CGRect sourceRect = [enclosingStackView convertRect:_undoButton.bounds fromView:_undoButton];
        _menuController.popoverPresentationController.sourceView = enclosingStackView;
        _menuController.popoverPresentationController.sourceRect = sourceRect;
    } else {
        _menuController.popoverPresentationController.sourceView = nil;
        _menuController.popoverPresentationController.barButtonItem = self;
    }
    
    return _menuController;
}

- (UIAlertController *)_alertControllerForCompactMenuPresentation;
{
    id <OUIUndoBarButtonItemTarget> target = _weak_undoBarButtonItemTarget;
    // the sheet will dismiss as soon as the user makes a choice, so they will have to tap again to get Redo.
    
    UIAlertController *undoController = [UIAlertController alertControllerWithTitle:nil
                                                                            message:nil
                                                                     preferredStyle:UIAlertControllerStyleActionSheet];
    
    
    if ([target canPerformAction:@selector(undo:) withSender:nil]) {
        [undoController addAction:[UIAlertAction actionWithTitle:OUILocalizedStringUndo()
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *action) {
                                                             if (target) {
                                                                 [target undo:nil];
                                                             }
                                                         }]];
    }
    if ([target canPerformAction:@selector(redo:) withSender:nil]) {
        [undoController addAction:[UIAlertAction actionWithTitle:OUILocalizedStringRedo()
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction *action) {
                                                             if (target) {
                                                                 [target redo:nil];
                                                             }
                                                         }]];
    }
    [undoController addAction:[UIAlertAction actionWithTitle:OACancel()
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil]];
    
    return undoController;
}

- (void)_touchDown:(id)sender;
{
    if (!self.enabled)
        return;
    
    if ([OUIUndoBarButtonItem dismissUndoMenu] == YES) {
        return;
    }
    
    // If we can only redo, then run our menu on touch-down. Otherwise do nothing and let the guesture recognizers to whatever they detect.
    if (!_canUndo && _canRedo) {
        id <OUIUndoBarButtonItemTarget> target = _weak_undoBarButtonItemTarget;
        if ([target respondsToSelector:@selector(willPresentMenuForUndoRedo)]) {
            [target willPresentMenuForUndoRedo];
        }
        [self _showUndoMenu];
    }
}

- (void)_undoButtonTap:(id)sender;
{
    id <OUIUndoBarButtonItemTarget> target = _weak_undoBarButtonItemTarget;
    [target undo:self];
}

- (void)_undoButtonPressAndHold:(id)sender;
{
    OBASSERT([sender isKindOfClass:[UILongPressGestureRecognizer class]]);
    UILongPressGestureRecognizer *longPressGestureRecognizer = (UILongPressGestureRecognizer *)sender;
    
    if (longPressGestureRecognizer.state == UIGestureRecognizerStateBegan) {
        [self _showUndoMenu];
    }
}

static BOOL DidDismissAnyMenus;
+ (BOOL)dismissUndoMenu;
{
    DidDismissAnyMenus = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIUndoBarButtonItemDismissMenuNotification object:nil];
    return DidDismissAnyMenus;
}

- (void)_reallyDismissUndoMenu:(id)unused;
{
    if (_menuController.presentingViewController) {
        [_menuController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
        DidDismissAnyMenus = YES;
    }
}

@end

@implementation UIViewController (OUIUndoBarButtonItemPresentation)

- (void)presentMenuForUndoBarButtonItem:(OUIUndoBarButtonItem *)barButtonItem;
{
    if (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact || self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact) {
        UIAlertController *undoController = [barButtonItem _alertControllerForCompactMenuPresentation];
        // Just in case this want's to present as a popover, we'll give it a button to present from.
        undoController.popoverPresentationController.barButtonItem = barButtonItem;
        [self presentViewController:undoController
                           animated:YES
                         completion:nil];  // we could update the "Undo" title of the button to "Redo" in this case, if redo were the only possible option, but this is consistent with the regular width trait class behavior
    }
    else {
        // we can use our popover
        UINavigationController *navigationController = [self isKindOfClass:[UINavigationController class]] ? (UINavigationController *)self : self.navigationController;
        OUIMenuController *menuController = [barButtonItem _menuControllerForRegularMenuPresentationInWindow:self.view.window];
        [menuController.popoverPresentationController addManagedBarButtonItemsFromNavigationController:navigationController];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:OUIUndoPopoverWillShowNotification object:barButtonItem];
        [self presentViewController:menuController animated:YES completion:NULL];
    }
}

@end

NSString *OUILocalizedStringUndo(void)
{
    static NSString *string;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        string = NSLocalizedStringFromTableInBundle(@"Undo", @"OmniUI", OMNI_BUNDLE, @"Undo button title");
    });
    return string;
}

NSString *OUILocalizedStringRedo(void)
{
    static NSString *string;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        string = NSLocalizedStringFromTableInBundle(@"Redo", @"OmniUI", OMNI_BUNDLE, @"Redo button title");
    });
    return string;
}
