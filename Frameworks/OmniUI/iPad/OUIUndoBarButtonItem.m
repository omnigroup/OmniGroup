// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIUndoBarButtonItem.h>

#import <OmniUI/OUIUndoButtonPopoverHelper.h>
#import <OmniUI/OUIUndoButton.h>
#import <OmniUI/OUIUndoButtonController.h>

RCS_ID("$Id$");

// OUIUndoBarButtonItemTarget
OBDEPRECATED_METHOD(-undoBarButtonItemWillShowPopover); // Use the OUIAppController single-popover helper instead.

NSString * const OUIUndoPopoverWillShowNotification = @"OUIUndoPopoverWillShowNotification";

// We don't implement this, but UIBarButtonItem doesn't declare that is does (though it really does). If UIBarButtonItem doesn't implement coder later, then our subclass method will never get called and we'll never fail on the call to super.
@interface UIBarButtonItem (NSCoding) <NSCoding>
@end

@interface OUIUndoBarButtonItem (/*Private*/)
- (void)_startObservingUndoManager;
- (void)_stopObservingUndoManager;
- (void)_updateStateFromUndoMananger:(NSNotification *)note;
- (void)_showUndoMenu;

// Internal actions
- (void)_touchDown:(id)sender;
- (void)_undoButtonTap:(id)sender;
- (void)_undoButtonPressAndHold:(id)sender;
@end

@implementation OUIUndoBarButtonItem

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
    self->_undoButton = [[OUIUndoButton alloc] init];
    [self->_undoButton sizeToFit];
    self.customView = self->_undoButton;

    // adjust the text label because UIButton and UITitleBarButton place their labels 1 apple point off from each other by default.
    [self->_undoButton setTitleEdgeInsets:UIEdgeInsetsMake(0,0,1,0)];
    
    [self->_undoButton addTarget:self action:@selector(_touchDown:) forControlEvents:UIControlEventTouchDown];

    self->_tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_undoButtonTap:)];
    [self->_undoButton addGestureRecognizer:self->_tapRecognizer];

    self->_longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_undoButtonPressAndHold:)];
    [self->_undoButton addGestureRecognizer:self->_longPressRecognizer];
    
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
    if (_undoManager) {
        [self _stopObservingUndoManager];
        [_undoManager release];
    }
    
    [_undoButton removeTarget:self action:@selector(_touchDown:) forControlEvents:UIControlEventTouchDown];
    
    [_undoButton removeGestureRecognizer:_tapRecognizer];
    [_tapRecognizer release];
    
    [_longPressRecognizer release];
    [_undoButton removeGestureRecognizer:_longPressRecognizer];
    
    [_undoButton release];
    [_buttonController release];
    [super dealloc];
}

#pragma mark -
#pragma mark API

@synthesize undoManager = _undoManager;
- (void)setUndoManager:(NSUndoManager *)undoManager;
{
    if (_undoManager == undoManager)
        return;
    
    if (_undoManager)
        [self _stopObservingUndoManager];

    [_undoManager release];
    _undoManager = [undoManager retain];

    if (_undoManager)
        [self _startObservingUndoManager];
    
    [self _updateStateFromUndoMananger:nil];
}

@synthesize undoBarButtonItemTarget = _undoBarButtonItemTarget;
@synthesize button = _undoButton;

- (void)setNormalBackgroundImage:(UIImage *)image;
{
    [_undoButton setNormalBackgroundImage:image];
}

- (void)setHighlightedBackgroundImage:(UIImage *)image;
{
    [_undoButton setHighlightedBackgroundImage:image];
}

#pragma mark -
#pragma mark UIBarButtonItem subclass

- (void)setEnabled:(BOOL)enabled;
{
    [super setEnabled:enabled];
    [self _updateStateFromUndoMananger:nil];
}

#pragma mark -
#pragma mark Private

- (void)_startObservingUndoManager;
{
    OBPRECONDITION(_undoManager);
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_updateStateFromUndoMananger:) name:NSUndoManagerDidUndoChangeNotification object:_undoManager];
    [center addObserver:self selector:@selector(_updateStateFromUndoMananger:) name:NSUndoManagerDidRedoChangeNotification object:_undoManager];
    [center addObserver:self selector:@selector(_updateStateFromUndoMananger:) name:NSUndoManagerWillCloseUndoGroupNotification object:_undoManager];
}

- (void)_stopObservingUndoManager;
{
    OBPRECONDITION(_undoManager);
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:NSUndoManagerDidUndoChangeNotification object:_undoManager];
    [center removeObserver:self name:NSUndoManagerDidRedoChangeNotification object:_undoManager];
    [center removeObserver:self name:NSUndoManagerWillCloseUndoGroupNotification object:_undoManager];
}

- (void)_updateStateFromUndoMananger:(NSNotification *)note;
{
    OBPRECONDITION(!note || ([note object] == _undoManager));
    
    // We just use the undo manager notifications to determine *when* to ask the target whether it can undo/redo. Likely the target will just use -[NSUndoManager can{Undo,Redo}], but in some cases it might have additional restrictions.
    
    if (note && 
        [[note name] isEqualToString:NSUndoManagerWillCloseUndoGroupNotification] &&
        [_undoManager groupingLevel] > 1) {
        return;
    }
    
    BOOL enabled = [self isEnabled];

    if (enabled) {
        _canUndo = [_undoBarButtonItemTarget canPerformAction:@selector(undo:) withSender:self];
        _canRedo = [_undoBarButtonItemTarget canPerformAction:@selector(redo:) withSender:self];
        
        enabled &= (_canUndo || _canRedo);
    }
    
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
    [_undoButton setEnabled:enabled];
}

- (void)_showUndoMenu;
{
    if (!_buttonController) {
        _buttonController = [[OUIUndoButtonController alloc] initWithNibName:nil bundle:nil];
        _buttonController.undoBarButtonItemTarget = _undoBarButtonItemTarget;
    }
    
    if (![_buttonController isMenuVisible]) {
        [[OUIUndoButtonPopoverHelper sharedPopoverHelper] dismissPopoverAnimated:NO];
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
    [[OUIUndoButtonPopoverHelper sharedPopoverHelper] dismissPopoverAnimated:YES];
    
    if (_undoBarButtonItemTarget)
        [_undoBarButtonItemTarget undo:self];
}

- (void)_undoButtonPressAndHold:(id)sender;
{
    [self _showUndoMenu];
}

- (BOOL)dismissUndoMenu;
{
    if (_buttonController) {
        return [_buttonController dismissUndoMenu];
    }
    return NO;
}
@end
