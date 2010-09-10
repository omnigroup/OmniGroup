// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIToolbarViewController.h>

#import <OmniUI/OUIDocumentPickerBackgroundView.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/UIView-OUIExtensions.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define TOOLBAR_DEBUG(format, ...) NSLog(@"TVB: " format, ## __VA_ARGS__)
#else
    #define TOOLBAR_DEBUG(format, ...)
#endif

@interface OUIToolbarViewControllerToolbar : UIToolbar
@end

@interface OUIToolbarViewController (/*Private*/)
- (void)_prepareViewControllerForContainment:(UIViewController *)soonToBeInnerViewController hidden:(BOOL)hidden;
- (void)_animationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
@end

@implementation OUIToolbarViewController

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_toolbar release];
    [_contentView release];
    [_innerViewController release];
    [super dealloc];
}

- (UIToolbar *)toolbar;
{
    [self view]; // make sure it is created
    return _toolbar;
}

@synthesize innerViewController = _innerViewController;

static void _setInnerViewController(OUIToolbarViewController *self, UIViewController *viewController, BOOL forAnimation)
{
    [self view];
    
    if (self->_innerViewController) {
        // Animation setup has already done this
        if (!forAnimation)
            [self->_innerViewController willResignInnerToolbarController:self animated:forAnimation];

        // Might have been unloaded already -- don't provoke a reload.
        if ([self->_innerViewController isViewLoaded])
            [self->_innerViewController.view removeFromSuperview];
        [self->_innerViewController release];
        self->_innerViewController = nil;
        
        // Will get done at the end of animation
        if (!forAnimation)
            [self->_innerViewController didResignInnerToolbarController:self];
            
    }
    
    if (viewController) {
        // Animation setup has already done this
        if (!forAnimation) {
            [self _prepareViewControllerForContainment:viewController hidden:NO];
            [viewController willBecomeInnerToolbarController:self animated:forAnimation]; // This call requires we are the right size. Could have *another* call for will-prepare, if needed
        }

        OUIDocumentPickerBackgroundView *backgroundView = (OUIDocumentPickerBackgroundView *)self.view;
        
        self->_innerViewController = [viewController retain];
        OBASSERT(self->_innerViewController.view.superview == self->_contentView); // done by -prepareViewControllerForContainment:
        [self->_contentView layoutIfNeeded];
        self->_innerViewController.view.hidden = NO;
        [self->_toolbar setItems:viewController.toolbarItems animated:forAnimation];
        backgroundView.editing = viewController.isEditingViewController;
        [self->_innerViewController didBecomeInnerToolbarController:self];
    }
}

- (void)setInnerViewController:(UIViewController *)viewController;
{
    TOOLBAR_DEBUG(@"Switching from %@ to %@", _innerViewController, viewController);
    _setInnerViewController(self, viewController, NO/*forAnimation*/);

    // In case someone claims they were going to do an animated switch but then does a non-animated one.
    [[OUIAppController controller] hideActivityIndicator];
}

- (void)_prepareViewControllerForContainment:(UIViewController *)soonToBeInnerViewController hidden:(BOOL)hidden;
{
    OBPRECONDITION(_contentView);
    
    UIView *innerView = soonToBeInnerViewController.view;
    CGRect contentBounds = _contentView.bounds;
    innerView.frame = contentBounds;

    [innerView layoutIfNeeded];

    // Add the view *now*, but make it hidden. This allows the caller to make coordinate system transforms between this view and the current inner view.
    if (hidden)
        innerView.hidden = YES;
    else {
        // Might have already prepared if we just wanted to get the view ready.
        //OBASSERT(innerView.hidden == NO);
    }

    [_contentView addSubview:innerView];
}

- (void)willAnimateToInnerViewController:(UIViewController *)viewController;
{
    OBPRECONDITION(_didStartActivityIndicator == NO); // should have stopped it by now.
    
    UIView *view = [_innerViewController prepareToResignInnerToolbarControllerAndReturnParentViewForActivityIndicator:self];
    if (view) {
        _didStartActivityIndicator = YES;
        [[OUIAppController controller] showActivityIndicatorInView:view];
    }
    
    if (viewController)
        [self _prepareViewControllerForContainment:viewController hidden:YES];
}

typedef struct {
    UIView *animatingView;
    UIViewController *toViewController;
    UIView *fromView;
} AnimationContext;

- (void)setInnerViewController:(UIViewController *)viewController animatingFromView:(UIView *)fromView rect:(CGRect)fromViewRect toView:(UIView *)toView rect:(CGRect)toViewRect;
{
    OBPRECONDITION(viewController);
    OBPRECONDITION(_innerViewController != viewController);

    
    TOOLBAR_DEBUG(@"Animating from %@ to %@", _innerViewController, viewController);
    TOOLBAR_DEBUG(@"  fromView %@", [fromView shortDescription]);
    TOOLBAR_DEBUG(@"  toView %@", [toView shortDescription]);
    
    OBASSERT([fromView isDescendantOfView:_innerViewController.view]);
    OBASSERT([toView isDescendantOfView:viewController.view]);
    
    // Disable further clicks. Our background view has a hack to eat events. Also, animate between an editing and non-editing image.
    OUIDocumentPickerBackgroundView *backgroundView = (OUIDocumentPickerBackgroundView *)self.view;
    backgroundView.editing = viewController.isEditingViewController;
    
    // We'll be hiding these views while animating; shouldn't be hidden yet.
    OBASSERT(fromView.layer.hidden == NO);
    OBASSERT(toView.layer.hidden == NO);
    
    // Get the document's view controller properly configured and send the 'will' notifications
    [_innerViewController willResignInnerToolbarController:self animated:YES];
    [self _prepareViewControllerForContainment:viewController hidden:YES];
    [viewController willBecomeInnerToolbarController:self animated:YES];
    
    // The target view won't be properly sized until we execute the lines above.
    if (CGRectIsEmpty(toViewRect))
        toViewRect = toView.bounds;
    if (CGRectIsEmpty(fromViewRect))
        fromViewRect = fromView.bounds;
    
    UIView *view = self.view;
    CGRect sourcePreviewFrame = [fromView convertRect:fromViewRect toView:view];
    CGRect targetPreviewFrame = [toView convertRect:toViewRect toView:view];
    
    // If we are zoomed way in, this animation isn't going to look great and we'll end up crashing trying to build a static image anyway.
    BOOL zoomed;
    {
        CGRect bounds = view.bounds;
        
        zoomed = (sourcePreviewFrame.size.width > 2 * bounds.size.width ||
                  sourcePreviewFrame.size.height > 2 * bounds.size.height ||
                  targetPreviewFrame.size.width > 2 * bounds.size.width ||
                  targetPreviewFrame.size.height > 2 * bounds.size.height);
    }
    
    if (zoomed) {
        AnimationContext *ctx = calloc(1, sizeof(*ctx));
        ctx->toViewController = [viewController retain];
        
        [self _animationDidStop:nil finished:NO context:ctx];
        return;
    }
    
    // Build our animating view in its starting configuration.
    UIView *animatingView = [[UIView alloc] initWithFrame:sourcePreviewFrame];

    // We'll use this view to fade in the new image.
    UIView *innerSnapshotView = [[UIView alloc] initWithFrame:animatingView.bounds];
    [animatingView addSubview:innerSnapshotView];
    [innerSnapshotView release];
    
    // The animating view should float above other views (like the neighboring proxies in the document picker).
    animatingView.layer.zPosition = 1;
        
    // We need to replicate the shadow edges that we expect the from/to views to have.
    NSArray *shadowEdges = OUIViewAddShadowEdges(animatingView);
    OUIViewLayoutShadowEdges(animatingView, shadowEdges, YES/*flip*/);
    
    UIImage *fromImage = [fromView snapshotImage];
    UIImage *toImage = [toView snapshotImage];
    
#if 0 && defined(DEBUG)
    {
        NSError *error = nil;
        if (![UIImagePNGRepresentation(fromImage) writeToFile:[@"~/Documents/from.png" stringByExpandingTildeInPath] options:0 error:&error])
            NSLog(@"Unable to write PNG: %@", [error toPropertyList]);
        if (![UIImagePNGRepresentation(toImage) writeToFile:[@"~/Documents/to.png" stringByExpandingTildeInPath] options:0 error:&error])
            NSLog(@"Unable to write PNG: %@", [error toPropertyList]);
    }
#endif
    
    animatingView.layer.contents = (id)[fromImage CGImage];
    animatingView.layer.contentsGravity = kCAGravityResize;

    innerSnapshotView.layer.contents = (id)[toImage CGImage];
    innerSnapshotView.layer.contentsGravity = kCAGravityResize;
    innerSnapshotView.alpha = 0;
    
    // The 'to' view is already hidden. Replace the from view with our animating view.
    fromView.hidden = YES;
    [view addSubview:animatingView];
    
    static const CGFloat animationDuration = 0;
    
    TOOLBAR_DEBUG(@"  sourcePreviewFrame = %@", NSStringFromCGRect(sourcePreviewFrame));
    TOOLBAR_DEBUG(@"  targetPreviewFrame = %@", NSStringFromCGRect(targetPreviewFrame));
    
    // Animate to the "new" state.
    
    AnimationContext *ctx = calloc(1, sizeof(*ctx));
    ctx->animatingView = animatingView; // Taking reference from init above
    ctx->toViewController = [viewController retain];
    ctx->fromView = [fromView retain];
    
    [UIView beginAnimations:@"inner view controller switch" context:ctx];
    if (animationDuration > 0) // setting to zero will turn off the animation
        [UIView setAnimationDuration:animationDuration];
    [UIView setAnimationDelegate:self];
    [UIView setAnimationDidStopSelector:@selector(_animationDidStop:finished:context:)];
    {
        animatingView.frame = targetPreviewFrame;
        OUIViewLayoutShadowEdges(animatingView, shadowEdges, YES/*flip*/);
        innerSnapshotView.frame = animatingView.bounds;
        innerSnapshotView.alpha = 1;
    }
    [UIView commitAnimations];
}

- (void)setInnerViewController:(UIViewController *)viewController animatingView:(UIView *)fromView toView:(UIView *)toView;
{
    [self setInnerViewController:viewController animatingFromView:fromView rect:CGRectZero toView:toView rect:CGRectZero];
}

- (void)_animationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
{
    AnimationContext *ctx = context;
    
    // _setInnerViewController expects us to do this since the 'will' got done by us when we started the animation
    [_innerViewController didResignInnerToolbarController:self];
    _setInnerViewController(self, ctx->toViewController, YES/*forAnimation*/);
    [ctx->toViewController release];

    [ctx->animatingView removeFromSuperview];
    [ctx->animatingView release];
    
    // We hid this when animating, so put it back.
    OBASSERT(ctx->fromView.hidden == YES);
    ctx->fromView.hidden = NO;
    [ctx->fromView release];
    
    if (_didStartActivityIndicator) {
        _didStartActivityIndicator = NO;
        [[OUIAppController controller] hideActivityIndicator];
    }

    free(ctx);
}

@synthesize resizesToAvoidKeyboard = _resizesToAvoidKeyboard;
- (void)setResizesToAvoidKeyboard:(BOOL)resizesToAvoidKeyboard;
{
    if (_resizesToAvoidKeyboard == resizesToAvoidKeyboard)
        return;
    _resizesToAvoidKeyboard = resizesToAvoidKeyboard;
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (resizesToAvoidKeyboard) {
        [center addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
        [center addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    } else {
        [center removeObserver:self name:UIKeyboardWillShowNotification object:nil];
        [center removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    }
}

NSString * const OUIToolbarViewControllerResizedForKeyboard = @"OUIToolbarViewControllerResizedForKeyboard";

- (void)keyboardWillShow:(NSNotification *)note;
{
    OBPRECONDITION(_contentView);
    
    // Documentation, mail or other modal view atop us -- the keyboard isn't for us. This has an implicit assumption that the keyboard will go away before the modal view controller.
    if (self.modalViewController)
        return;
    
    // Resize our content view so that it isn't obscured by the keyboard. Our superview is the background view, who has the window as its superview. Window coordinates are in device space (unrotated), but our superview will have orientation correct coordinates. The keyboard will have device coordinates (unrotated).
#ifdef OMNI_ASSERTIONS_ON
    OUIDocumentPickerBackgroundView *backgroundView = (OUIDocumentPickerBackgroundView *)self.view;
#endif
    OBASSERT(_contentView.superview == backgroundView);
    OBASSERT(backgroundView.superview == backgroundView.window);
    
    //NSLog(@"will show %@", note);
    NSValue *keyboardEndFrameValue = [[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey];
    OBASSERT(keyboardEndFrameValue);
    CGRect keyboardRectInBounds = [_contentView convertRect:[keyboardEndFrameValue CGRectValue] fromView:nil];
    //NSLog(@"keyboardRectInBounds = %@", NSStringFromRect(keyboardRectInBounds));
    
    // We should directly in the window and taking up the whole application-available frame.
    CGRect appSpaceInBounds = [_contentView convertRect:_contentView.window.screen.applicationFrame fromView:nil];
    //NSLog(@"appSpaceInBounds %@", NSStringFromRect(appSpaceInBounds));

    // We get notified of the keyboard appearing, but with it fully off screen if the hardware keyboard is enabled. If we don't need to adjust anything, bail.
    if (!CGRectIntersectsRect(appSpaceInBounds, keyboardRectInBounds))
        return;
        
    // The keyboard will come up out of the bottom. Trim our height so that our max-y avoids it.
    CGRect contentBounds = _contentView.bounds;
    CGRect contentBoundsAvoidingKeyboard = contentBounds;
    contentBoundsAvoidingKeyboard.size.height = CGRectGetMinY(keyboardRectInBounds) - CGRectGetMinY(contentBounds);
    //NSLog(@"contentBoundsAvoidingKeyboard %@", NSStringFromRect(contentBoundsAvoidingKeyboard));
    OBASSERT(!CGRectIntersectsRect(keyboardRectInBounds, contentBoundsAvoidingKeyboard));
    
    [UIView beginAnimations:@"avoid keyboard" context:NULL];
    {
        [UIView setAnimationDuration:[[[note userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue]];
        [UIView setAnimationCurve:[[[note userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];
        
        _contentView.frame = [_contentView convertRect:contentBoundsAvoidingKeyboard toView:_contentView.superview];
        [[NSNotificationCenter defaultCenter] postNotificationName:OUIToolbarViewControllerResizedForKeyboard object:self];
    }
    [UIView commitAnimations];

}

- (void)keyboardWillHide:(NSNotification *)note;
{
    // Documentation, mail or other modal view atop us -- the keyboard isn't for us. This has an implicit assumption that the keyboard will go away before the modal view controller.
    if (self.modalViewController)
        return;

    // Adjust our content view to cover everything but the toolbar.
    OUIDocumentPickerBackgroundView *backgroundView = (OUIDocumentPickerBackgroundView *)self.view;
    CGRect backgroundBounds = backgroundView.bounds;
    CGRect toolbarFrame = _toolbar.frame;

    CGRect contentFrame, dummy;
    CGRectDivide(backgroundBounds, &dummy, &contentFrame, CGRectGetHeight(toolbarFrame), CGRectMinYEdge);
    
    [UIView beginAnimations:@"done avoiding keyboard" context:NULL];
    {
        [UIView setAnimationDuration:[[[note userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue]];
        [UIView setAnimationCurve:[[[note userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];

        _contentView.frame = contentFrame;
    }
    [UIView commitAnimations];

//    [[NSNotificationCenter defaultCenter] postNotificationName:OUIToolbarViewControllerResizedForKeyboard object:self];
}

#pragma mark -
#pragma mark UIViewController subclass

- (void)loadView;
{
    /*
     We have three views:

     1) A background view, our main view, that always spans the full device (so we could hide the toolbar someday w/o it changing)
     
     Subviews of the main background view:
     
     2) A toolbar
     3) A content view that covers the whole background execpt the toolbar area OR the area covered by the keyboard, if we are needing to avoid it.
     
     */
    
    static const CGFloat kToolbarHeight = 44;
    static const CGFloat kStartingSize = 200; // whatever -- just something so we can lay stuff out and let autosizing take over.
    
    OUIDocumentPickerBackgroundView *view = [[OUIDocumentPickerBackgroundView alloc] initWithFrame:CGRectMake(0, 0, kStartingSize, kStartingSize)];
    view.autoresizesSubviews = YES;
    
    [view setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];

    _toolbar = [[OUIToolbarViewControllerToolbar alloc] initWithFrame:CGRectMake(0, 0, kStartingSize, kToolbarHeight)];
    _toolbar.barStyle = UIBarStyleBlack;
    [_toolbar setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin];

    // Get the height right, without letting the toolbar get super wide before our view gets sized to window size.
    [_toolbar sizeToFit];
    CGRect toolbarFrame = _toolbar.frame;
    toolbarFrame.size.width = view.bounds.size.width;
    _toolbar.frame = toolbarFrame;
    [view addSubview:_toolbar];
    
    _contentView = [[UIView alloc] initWithFrame:CGRectMake(0, CGRectGetHeight(toolbarFrame), kStartingSize, kStartingSize - CGRectGetHeight(toolbarFrame))];
    [_contentView setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    [view addSubview:_contentView];

    // If there was a low memory warning, we might actually be getting called for the second time.
    if (_innerViewController) {
        [self _prepareViewControllerForContainment:_innerViewController hidden:NO];
        [_toolbar setItems:_innerViewController.toolbarItems animated:NO];
    }

    [self setView:view];
    [view release];
}

- (void)viewDidUnload;
{
    [super viewDidUnload];
    
    [_toolbar release];
    _toolbar = nil;
    
    [_contentView release];
    _contentView = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
{
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration;
{
    [_innerViewController willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation;
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [_innerViewController didRotateFromInterfaceOrientation:fromInterfaceOrientation];
}

#pragma mark -
#pragma mark UIResponder subclass

- (NSUndoManager *)undoManager;
{
    // By default, if you send -undoManager to a view, it'll go up the responder chain and if it doesn't find one, UIWindow will create one.
    // We want to ensure that we don't get an implicitly created undo manager (OUIDocument/OUISingleDocumentAppController have other assertions to make sure that only the document's undo manager is used).
    OBASSERT_NOT_REACHED("This is probably not the -undoManager you want");
    return nil;
}

@end

@implementation OUIToolbarViewControllerToolbar

// Allow items on the main toolbar to find the inner toolbar controller. UIKit's notion of responder chain starts with the receiving control, NOT the containing window's first responder. Our embedding of one UIViewController inside another means that the inner view controller couldn't easily get toolbar actions. This avoids having to write patches from AppController subclasses.
- (UIResponder *)nextResponder;
{
    UIView *backgroundView = (UIView *)[super nextResponder];
    OUIToolbarViewController *controller = (OUIToolbarViewController *)[backgroundView nextResponder];
    
    OBASSERT([controller isKindOfClass:[OUIToolbarViewController class]]);
    OBASSERT(controller.view == backgroundView);

    // If we have an inner view controller, go to it and skip the background view and the OUIToolbarViewController. They'll get hit after the view of the inner view controller.
    UIViewController *innerViewController = controller.innerViewController;
    if (innerViewController) {
        OBASSERT([innerViewController nextResponder] == [innerViewController.view superview]);
        OBASSERT([[innerViewController nextResponder] nextResponder] == backgroundView);
        return innerViewController;
    }
    
    return backgroundView; // normal next responder
}

@end


@implementation UIViewController (OUIToolbarViewControllerExtensions)
- (UIView *)prepareToResignInnerToolbarControllerAndReturnParentViewForActivityIndicator:(OUIToolbarViewController *)toolbarViewController;
{
    return self.view;
}
- (void)willResignInnerToolbarController:(OUIToolbarViewController *)toolbarViewController animated:(BOOL)animated;
{
    // For subclasses
}
- (void)didResignInnerToolbarController:(OUIToolbarViewController *)toolbarViewController;
{
    // For subclasses
}
- (void)willBecomeInnerToolbarController:(OUIToolbarViewController *)toolbarViewController animated:(BOOL)animated;
{
    // For subclasses
}
- (void)didBecomeInnerToolbarController:(OUIToolbarViewController *)toolbarViewController;
{
    // For subclasses
}
- (BOOL)isEditingViewController;
{
    return YES;
}
@end
