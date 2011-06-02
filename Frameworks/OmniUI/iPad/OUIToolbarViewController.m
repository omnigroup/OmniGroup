// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIToolbarViewController.h>

#import "OUIParameters.h"

#import <OmniUI/OUIAppController.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import "OUIToolbarViewController-Internal.h"
#import "OUIToolbarViewControllerToolbar.h"
#import "OUIToolbarViewControllerBackgroundView.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define TOOLBAR_DEBUG(format, ...) NSLog(@"TVB: " format, ## __VA_ARGS__)
#else
    #define TOOLBAR_DEBUG(format, ...)
#endif

@interface OUIToolbarViewController (/*Private*/)
- (void)_prepareViewControllerForContainment:(UIViewController *)soonToBeInnerViewController hidden:(BOOL)hidden;
- (void)_animationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
@end

@implementation OUIToolbarViewController

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_innerViewController release];
    [super dealloc];
}

- (UIToolbar *)toolbar;
{
    OUIToolbarViewControllerBackgroundView *view = (OUIToolbarViewControllerBackgroundView *)self.view;
    return view.toolbar;
}

@synthesize lastKeyboardHeight = _lastKeyboardHeight;
@synthesize innerViewController = _innerViewController;

- (CGFloat)interItemPadding
{
    return kOUIToolbarIteritemPadding;
}

static void _setInnerViewController(OUIToolbarViewController *self, UIViewController *viewController, BOOL forAnimation)
{
    [self view];
    
    if (self->_innerViewController) {
        // Animation setup has already done this
        if (!forAnimation)
            [self->_innerViewController willResignInnerToolbarController:self animated:forAnimation];
        else {
            OBASSERT(self->_animatingAwayFromCurrentInnerViewController);
        }
        
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
        } else {
            OBASSERT(self->_animatingAwayFromCurrentInnerViewController);
            self->_animatingAwayFromCurrentInnerViewController = NO; // all done animating
        }

        OUIToolbarViewControllerBackgroundView *view = (OUIToolbarViewControllerBackgroundView *)self.view;
        
        self->_innerViewController = [viewController retain];
        OBASSERT(self->_innerViewController.view.superview == view.contentView); // done by -prepareViewControllerForContainment:
        [view.contentView layoutIfNeeded];
        self->_innerViewController.view.hidden = NO;
        [view.toolbar setItems:viewController.toolbarItems animated:forAnimation];
        view.editing = viewController.isEditingViewController;
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

- (void)adjustSizeToMatch:(UIViewController *)soonToBeInnerViewController;
{
    OUIToolbarViewControllerBackgroundView *backgroundView = (OUIToolbarViewControllerBackgroundView *)self.view;
    
    UIView *innerView = soonToBeInnerViewController.view;
    CGRect contentBounds = backgroundView.contentView.bounds;
    innerView.frame = contentBounds;
    
    [innerView layoutIfNeeded];
}

- (void)_prepareViewControllerForContainment:(UIViewController *)soonToBeInnerViewController hidden:(BOOL)hidden;
{
    [self adjustSizeToMatch:soonToBeInnerViewController];

    OUIToolbarViewControllerBackgroundView *backgroundView = (OUIToolbarViewControllerBackgroundView *)self.view;
    UIView *innerView = soonToBeInnerViewController.view;

    // Add the view *now*, but make it hidden. This allows the caller to make coordinate system transforms between this view and the current inner view.
    if (hidden)
        innerView.hidden = YES;
    else {
        // Might have already prepared if we just wanted to get the view ready.
        //OBASSERT(innerView.hidden == NO);
    }

    [backgroundView.contentView addSubview:innerView];
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

- (void)setToolbarHidden:(BOOL)hidden;
{
    UIToolbar *toolbar = self.toolbar;

    if (toolbar.hidden == hidden)
        return;

    toolbar.hidden = hidden;
    [self.view setNeedsLayout];
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
    OBPRECONDITION(fromView != nil);
    OBPRECONDITION(toView != nil);

    TOOLBAR_DEBUG(@"Animating from %@ to %@", _innerViewController, viewController);
    TOOLBAR_DEBUG(@"  fromView %@", [fromView shortDescription]);
    TOOLBAR_DEBUG(@"  toView %@", [toView shortDescription]);
    
    OBASSERT([fromView isDescendantOfView:_innerViewController.view]);
    OBASSERT([toView isDescendantOfView:viewController.view]);
    
    // Disable further clicks. Our background view has a hack to eat events. Also, animate between an editing and non-editing image.
    OUIToolbarViewControllerBackgroundView *backgroundView = (OUIToolbarViewControllerBackgroundView *)self.view;
    backgroundView.editing = viewController.isEditingViewController;
    
    // We'll be hiding these views while animating; shouldn't be hidden yet.
    OBASSERT(fromView.layer.hidden == NO);
    OBASSERT(toView.layer.hidden == NO);
    
    // Get the document's view controller properly configured and send the 'will' notifications
    OBASSERT(_animatingAwayFromCurrentInnerViewController == NO);
    _animatingAwayFromCurrentInnerViewController = YES;
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
    if (targetPreviewFrame.size.width > sourcePreviewFrame.size.width)
        targetPreviewFrame.size.height = targetPreviewFrame.size.width * (sourcePreviewFrame.size.height / sourcePreviewFrame.size.width);
    else
        sourcePreviewFrame.size.height = sourcePreviewFrame.size.width * (targetPreviewFrame.size.height / targetPreviewFrame.size.width);
    
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
    
    // Make sure that if any views in the old inner view controller have been sent -setNeedsDisplay that they won't start trying to fill their layers as the CoreAnimation loop starts running. They are dead!
    [_innerViewController.view removeFromSuperview];
    
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

@synthesize animatingAwayFromCurrentInnerViewController = _animatingAwayFromCurrentInnerViewController;

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
    OBPRECONDITION([self isViewLoaded]);
    
    // Documentation, mail or other modal view atop us -- the keyboard isn't for us. This has an implicit assumption that the keyboard will go away before the modal view controller.
    if (self.modalViewController)
        return;
    
    // Resize our content view so that it isn't obscured by the keyboard. Our superview is the background view, who has the window as its superview. Window coordinates are in device space (unrotated), but our superview will have orientation correct coordinates. The keyboard will have device coordinates (unrotated).
    OUIToolbarViewControllerBackgroundView *backgroundView = (OUIToolbarViewControllerBackgroundView *)self.view;
    OBASSERT(backgroundView.superview == backgroundView.window);
    
    //NSLog(@"will show %@", note);
    NSValue *keyboardEndFrameValue = [[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey];
    OBASSERT(keyboardEndFrameValue);
    CGRect keyboardRectInBounds = [backgroundView convertRect:[keyboardEndFrameValue CGRectValue] fromView:nil];
    //NSLog(@"keyboardRectInBounds = %@", NSStringFromRect(keyboardRectInBounds));
    
    // We should directly in the window and taking up the whole application-available frame.
    CGRect appSpaceInBounds = [backgroundView convertRect:backgroundView.window.screen.applicationFrame fromView:nil];
    //NSLog(@"appSpaceInBounds %@", NSStringFromRect(appSpaceInBounds));

    // We get notified of the keyboard appearing, but with it fully off screen if the hardware keyboard is enabled. If we don't need to adjust anything, bail.
    if (!CGRectIntersectsRect(appSpaceInBounds, keyboardRectInBounds))
        return;
    
    // Since we can get multiple 'will show' notifications w/o a 'will hide' (when changing international keyboards changes the keyboard height), we can't assume that the contentView's height is the full unmodified height.
    
    // The keyboard will come up out of the bottom. Trim our height so that our max-y avoids it.
    CGFloat avoidedBottomHeight = CGRectGetMaxY(backgroundView.bounds) - CGRectGetMinY(keyboardRectInBounds);
    _lastKeyboardHeight = avoidedBottomHeight;
    
#ifdef OMNI_ASSERTIONS_ON
//    {
//        CGRect contentBoundsAvoidingKeyboard = contentBounds;
//        contentBoundsAvoidingKeyboard.size.height = availableContentHeight;
//        //NSLog(@"contentBoundsAvoidingKeyboard %@", NSStringFromRect(contentBoundsAvoidingKeyboard));
//        OBASSERT(!CGRectIntersectsRect(keyboardRectInBounds, contentBoundsAvoidingKeyboard));
//    }
#endif
    
    [UIView beginAnimations:@"avoid keyboard" context:NULL];
    {
        // Match the keyboard animation time and curve. Also, starting from the current position is very important. If we don't and we are jumping between two editable controls, our view size may bounce.
        [UIView setAnimationDuration:[[[note userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue]];
        [UIView setAnimationCurve:[[[note userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];
        [UIView setAnimationBeginsFromCurrentState:YES];
        
        backgroundView.avoidedBottomHeight = avoidedBottomHeight;
        [backgroundView layoutIfNeeded]; // since our notification says we have resized

        [[NSNotificationCenter defaultCenter] postNotificationName:OUIToolbarViewControllerResizedForKeyboard object:self];

        [backgroundView layoutIfNeeded]; // in case the notification moves anything else around
    }
    [UIView commitAnimations];

}

- (void)keyboardWillHide:(NSNotification *)note;
{
    OUIToolbarViewControllerBackgroundView *backgroundView = (OUIToolbarViewControllerBackgroundView *)self.view;

    // Documentation, mail or other modal view atop us -- the keyboard isn't for us. This has an implicit assumption that the keyboard will go away before the modal view controller.
    // Still, if the keyboard is gone, we need to make clear our avoidance.
    if (self.modalViewController) {
        OUIWithoutAnimating(^{
            backgroundView.avoidedBottomHeight = 0;
            [backgroundView layoutIfNeeded];
        });
        return;
    }

    // Remove the restriction on the content height
    [UIView beginAnimations:@"done avoiding keyboard" context:NULL];
    {
        // Match the keyboard animation time and curve. Also, starting from the current position is very important. If we don't and we are jumping between two editable controls, our view size may bounce.
        [UIView setAnimationDuration:[[[note userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue]];
        [UIView setAnimationCurve:[[[note userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];
        [UIView setAnimationBeginsFromCurrentState:YES];

        backgroundView.avoidedBottomHeight = 0;
        [backgroundView layoutIfNeeded];
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
    
    static const CGFloat kStartingSize = 200; // whatever -- just something so we can lay stuff out to start
    
    OUIToolbarViewControllerBackgroundView *view = [[OUIToolbarViewControllerBackgroundView alloc] initWithFrame:CGRectMake(0, 0, kStartingSize, kStartingSize)];
    [self setView:view]; // Have to do this before calling down into code that might as for our view

    // If there was a low memory warning, we might actually be getting called for the second time.
    if (_innerViewController) {
        [self _prepareViewControllerForContainment:_innerViewController hidden:NO];
        [view.toolbar setItems:_innerViewController.toolbarItems animated:NO];
    }

    [view release];
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
    [[OUIAppController controller] didRotateFromInterfaceOrientation:fromInterfaceOrientation];
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
