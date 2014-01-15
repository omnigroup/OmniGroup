// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIUndoBarButtonItem.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIUndoButton.h>
#import <OmniUI/OUIUndoButtonController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import "OUIParameters.h"

RCS_ID("$Id$");

// OUIUndoBarButtonItemTarget
OBDEPRECATED_METHOD(-undoBarButtonItemWillShowPopover); // Use the OUIAppController single-popover helper instead.

NSString * const OUIUndoPopoverWillShowNotification = @"OUIUndoPopoverWillShowNotification";

// We don't implement this, but UIBarButtonItem doesn't declare that is does (though it really does). If UIBarButtonItem doesn't implement coder later, then our subclass method will never get called and we'll never fail on the call to super.
@interface UIBarButtonItem (NSCoding) <NSCoding>
@end

@implementation OUIUndoBarButtonItem
{
    OUIUndoButton *_undoButton;

    NSMutableArray *_undoManagers;
    
    UITapGestureRecognizer *_tapRecognizer;
    UILongPressGestureRecognizer *_longPressRecognizer;

    __weak id <OUIUndoBarButtonItemTarget>  _weak_undoBarButtonItemTarget;
    OUIUndoButtonController *_buttonController;

    BOOL _canUndo, _canRedo;
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
    self->_undoManagers = [[NSMutableArray alloc] init];
    
    UIColor *tintColor = [OUIAppController controller].window.tintColor;
    self.tintColor = tintColor;
    self->_undoButton = [OUIUndoButton buttonWithType:UIButtonTypeSystem];

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

    return self;
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
    for (NSUndoManager *undoManager in _undoManagers)
        [self _stopObservingUndoManager:undoManager];
    
    [_undoButton removeTarget:self action:@selector(_touchDown:) forControlEvents:UIControlEventTouchDown];
    [_undoButton removeGestureRecognizer:_tapRecognizer];
    [_undoButton removeGestureRecognizer:_longPressRecognizer];
}

#pragma mark - API

- (void)addUndoManager:(NSUndoManager *)undoManager;
{
    OBPRECONDITION([_undoManagers indexOfObjectIdenticalTo:undoManager] == NSNotFound);
 
    [_undoManagers addObject:undoManager];
    [self _startObservingUndoManager:undoManager];
    [self _updateStateFromUndoMananger:nil];
}

- (void)removeUndoManager:(NSUndoManager *)undoManager;
{
    OBPRECONDITION([_undoManagers indexOfObjectIdenticalTo:undoManager] != NSNotFound);
    
    [self _stopObservingUndoManager:undoManager];
    [_undoManagers removeObjectIdenticalTo:undoManager];
    [self _updateStateFromUndoMananger:nil];
}

- (BOOL)hasUndoManagers;
{
    return [_undoManagers count] > 0;
}

- (void)updateState;
{
    [self _updateStateFromUndoMananger:nil];
}

@synthesize undoBarButtonItemTarget = _weak_undoBarButtonItemTarget;
@synthesize button = _undoButton;

#pragma mark -
#pragma mark Private

- (void)_startObservingUndoManager:(NSUndoManager *)undoManager;
{
    OBPRECONDITION(undoManager);
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_updateStateFromUndoMananger:) name:NSUndoManagerDidUndoChangeNotification object:undoManager];
    [center addObserver:self selector:@selector(_updateStateFromUndoMananger:) name:NSUndoManagerDidRedoChangeNotification object:undoManager];
    [center addObserver:self selector:@selector(_updateStateFromUndoMananger:) name:NSUndoManagerWillCloseUndoGroupNotification object:undoManager];
}

- (void)_stopObservingUndoManager:(NSUndoManager *)undoManager;
{
    OBPRECONDITION(undoManager);
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:NSUndoManagerDidUndoChangeNotification object:undoManager];
    [center removeObserver:self name:NSUndoManagerDidRedoChangeNotification object:undoManager];
    [center removeObserver:self name:NSUndoManagerWillCloseUndoGroupNotification object:undoManager];
}

- (void)_updateStateFromUndoMananger:(NSNotification *)note;
{
    NSUndoManager *undoManager = [note object];
    OBPRECONDITION(!note || ([_undoManagers indexOfObjectIdenticalTo:undoManager] != NSNotFound));
    
    // We just use the undo manager notifications to determine *when* to ask the target whether it can undo/redo. Likely the target will just use -[NSUndoManager can{Undo,Redo}], but in some cases it might have additional restrictions.

    if (note && 
        [[note name] isEqualToString:NSUndoManagerWillCloseUndoGroupNotification] &&
        [undoManager groupingLevel] > 1) {
        return;
    }

    id <OUIUndoBarButtonItemTarget> target = _weak_undoBarButtonItemTarget;
    _canUndo = [target canPerformAction:@selector(undo:) withSender:self];
    _canRedo = [target canPerformAction:@selector(redo:) withSender:self];
        
    BOOL enabled = (_canUndo || _canRedo);
    
    if (_canUndo) {
        // Tap should undo, press and hold should give menu
        _tapRecognizer.enabled = YES;
        _longPressRecognizer.enabled = YES;
    } else if (_canRedo) {
        // Touch-down should do menu
        _tapRecognizer.enabled = NO;
        _longPressRecognizer.enabled = NO; // our touch-down will do it.
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
    if (!_buttonController) {
        _buttonController = [[OUIUndoButtonController alloc] init];
        _buttonController.undoBarButtonItemTarget = _weak_undoBarButtonItemTarget;
        _buttonController.tintColor = self.tintColor;
    }
    
    if (!_buttonController.isMenuVisible) {
        [[OUIAppController controller] dismissPopoverAnimated:NO];
        [_buttonController showUndoMenuFromItem:self];
    }
}

- (void)_touchDown:(id)sender;
{
    if (!self.enabled)
        return;
    
    if ([_buttonController dismissUndoMenu])
        return;
    
    // If we can only redo, then run our menu on touch-down. Otherwise do nothing and let the guesture recognizers to whatever they detect.
    if (!_canUndo && _canRedo)
        [self _showUndoMenu];
}

- (void)_undoButtonTap:(id)sender;
{
    // Close any open popover if the undo toolbar item button is tapped. We can make popovers update themselves in many cases via KVO/notification/manual updating, but it isn't clear that this is useful (iWork closes the inspector popovers on undo). Also, there are cases where we can't update (for example, undoing past the creation of the inspected object) and would have to dismiss anyway.
    [[OUIAppController controller] dismissPopoverAnimated:YES];
    
    id <OUIUndoBarButtonItemTarget> target = _weak_undoBarButtonItemTarget;
    [target undo:self];
}

- (void)_undoButtonPressAndHold:(id)sender;
{
    [self _showUndoMenu];
}

- (BOOL)dismissUndoMenu;
{
    if (_buttonController)
        return [_buttonController dismissUndoMenu];
    return NO;
}
@end
