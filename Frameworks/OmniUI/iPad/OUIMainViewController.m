// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMainViewController.h>

#import "OUIParameters.h"

#import <OmniUI/OUIAppController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUIAnimationSequence.h>

#import "OUIMainViewController-Internal.h"
#import "OUIMainViewControllerBackgroundView.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define MAIN_VC_DEBUG(format, ...) NSLog(@"MAIN: " format, ## __VA_ARGS__)
#else
    #define MAIN_VC_DEBUG(format, ...)
#endif

@interface _OUIMainViewControllerTransitionView : UIView
- initWithFromView:(UIView *)fromView toView:(UIView *)toView sourcePreviewFrame:(CGRect)sourcePreviewFrame;
- (void)transitionToFrame:(CGRect)targetPreviewFrame;
@end

@implementation _OUIMainViewControllerTransitionView
{
    UIView *_innerSnapshotView;
}

- initWithFromView:(UIView *)fromView toView:(UIView *)toView sourcePreviewFrame:(CGRect)sourcePreviewFrame;
{
    if (!(self = [super initWithFrame:sourcePreviewFrame]))
        return nil;

    // We'll use this view to fade in the new image.
    _innerSnapshotView = [[UIView alloc] initWithFrame:self.bounds];
    [self addSubview:_innerSnapshotView];
    
    // The animating view should float above other views (like the neighboring item views in the document picker).
    self.layer.zPosition = 1;
    
    // We need to replicate the shadow edges that we expect the from/to views to have.
    //NSArray *shadowEdges = OUIViewAddShadowEdges(self);
    //OUIViewLayoutShadowEdges(self, shadowEdges, YES/*flip*/);
    
    UIImage *fromImage = [fromView snapshotImage];
    UIImage *toImage = [toView snapshotImage];
    
#if 0 && defined(DEBUG)
    {
        NSError *error = nil;
        if (![UIImagePNGRepresentation(fromImage) writeToFile:[@"~/tmp/from.png" stringByExpandingTildeInPath] options:0 error:&error])
            NSLog(@"Unable to write PNG: %@", [error toPropertyList]);
        if (![UIImagePNGRepresentation(toImage) writeToFile:[@"~/tmp/to.png" stringByExpandingTildeInPath] options:0 error:&error])
            NSLog(@"Unable to write PNG: %@", [error toPropertyList]);
    }
#endif
    
    self.layer.contents = (id)[fromImage CGImage];
    self.layer.contentsGravity = kCAGravityResize;
    
    _innerSnapshotView.layer.contents = (id)[toImage CGImage];
    _innerSnapshotView.layer.contentsGravity = kCAGravityResize;
    _innerSnapshotView.alpha = 0;
    
    return self;
}

- (void)transitionToFrame:(CGRect)targetPreviewFrame;
{
    self.frame = targetPreviewFrame;
    
    OBFinishPortingLater("What should we do for shadows? Do we even need the inner view now?");
    //OUIViewLayoutShadowEdges(transitionView, shadowEdges, YES/*flip*/);
    _innerSnapshotView.frame = self.bounds;
    _innerSnapshotView.alpha = 1;
}

- (void)dealloc;
{
    [_innerSnapshotView release];
    [super dealloc];
}

@end

@implementation OUIMainViewController

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_innerViewController release];
    [super dealloc];
}

@synthesize lastKeyboardHeight = _lastKeyboardHeight;

@synthesize innerViewController = _innerViewController;
- (void)setInnerViewController:(UIViewController *)viewController;
{
    [self setInnerViewController:viewController animated:NO fromView:nil toView:nil];
}

- (void)adjustSizeToMatch:(UIViewController *)soonToBeInnerViewController;
{
    OUIMainViewControllerBackgroundView *backgroundView = (OUIMainViewControllerBackgroundView *)self.view;
    
    UIView *innerView = soonToBeInnerViewController.view;
    OBASSERT(innerView); // should be a view
    OBASSERT(innerView.window == nil); // but it shouldn't be visible yet
    
    CGRect contentBounds = backgroundView.contentView.bounds;
    innerView.frame = contentBounds;

    // Don't provoke layout here. Some view controllers aren't ready to lay out until they have a parent view/view controller
    //[innerView layoutIfNeeded];
}

- (void)setToolbarHidden:(BOOL)hidden;
{
    OUIMainViewControllerBackgroundView *view = (OUIMainViewControllerBackgroundView *)self.view;
    UIToolbar *toolbar = view.toolbar;

    if (toolbar.hidden == hidden)
        return;

    toolbar.hidden = hidden;
    [self.view setNeedsLayout];
}

/*
 Performs a transition between the old inner view controller and a new one, possibly with animation. The from/to regions aren't passed in directly in this method, since the view controllers (particularly the 'to' controller) may not be able to answer that question while they aren't sized properly and in the view hierarchy. For example, the OUIDocumentPicker can't lay out items, get the item preview view and determine its frame until it is in the view. A nil region means that the view controller's main view is used (with its whole bounds).
 */
- (void)setInnerViewController:(UIViewController *)viewController animated:(BOOL)animated
                    fromRegion:(OUIMainViewControllerGetAnimationRegion)fromRegion
                      toRegion:(OUIMainViewControllerGetAnimationRegion)toRegion
              transitionAction:(void (^)(void))transitionAction;
{
    OBPRECONDITION([self isViewLoaded]);
    OBPRECONDITION(viewController);
    OBPRECONDITION(_innerViewController != viewController);
    OBPRECONDITION(!animated || fromRegion != nil);
    OBPRECONDITION(!animated || toRegion != nil);

    MAIN_VC_DEBUG(@"Change inner view controller from %@ to %@", _innerViewController, viewController);
    MAIN_VC_DEBUG(@"  animated %d", animated);
    MAIN_VC_DEBUG(@"  fromRegion %@", [fromRegion shortDescription]);
    MAIN_VC_DEBUG(@"  toRegion %@", [toRegion shortDescription]);
    
    // Disable further clicks. Our background view has a hack to eat events. Also, animate between an editing and non-editing image.
    OUIMainViewControllerBackgroundView *backgroundView = (OUIMainViewControllerBackgroundView *)self.view;
    backgroundView.editing = viewController.isEditingViewController;
    
    // Get the document's view controller properly configured and send the 'will' notifications.
    MAIN_VC_DEBUG(@"Prepare %@ for containment", [viewController shortDescription]);
    
    // Size the new and mark it hidden before it is added. This allows the caller to make coordinate system transforms between this view and the current inner view.
    [self adjustSizeToMatch:viewController];

    if (_innerViewController) {
        MAIN_VC_DEBUG(@"will-move-to:nil on %@", [_innerViewController shortDescription]);
        [_innerViewController willMoveToParentViewController:nil]; // -removeFromParentViewController doesn't call this, we have to
    }

    MAIN_VC_DEBUG(@"add-child:%@", [viewController shortDescription]);
    [self addChildViewController:viewController]; // This calls -willMoveToParentViewController:
    [backgroundView.contentView addSubview:viewController.view];
    backgroundView.toolbar = [viewController toolbarForMainViewController];
    
    // Now that we are in the view, provoke any transition action and layout so that the toView/toViewRect can be updated.
    if (transitionAction) {
        OUIWithoutAnimating(^{
            transitionAction();
            [viewController.view layoutIfNeeded];
        });
    }
    
    // Now that the new view controller's view is in the view hierarchy and sized right, we can ask for the from/to regions.
    UIView *fromView = nil, *toView = nil;
    CGRect fromViewRect = CGRectZero, toViewRect = CGRectZero;
    
    if (fromRegion)
        fromRegion(&fromView, &fromViewRect);
    if (toRegion)
        toRegion(&toView, &toViewRect);
    
    if (!fromView)
        fromView = _innerViewController.view;
    if (!toView)
        toView = viewController.view;
    
    OBASSERT((!fromView && !animated) || [fromView isDescendantOfView:_innerViewController.view]); // First setup with have no old view controller and shouldn't be animated
    OBASSERT([toView isDescendantOfView:viewController.view]);
    
    // We'll be hiding these views while animating; shouldn't be hidden yet.
    OBASSERT(fromView.layer.hidden == NO);
    OBASSERT(toView.layer.hidden == NO);
    
    UIView *view = self.view;
    CGRect sourcePreviewFrame = CGRectZero;
    CGRect targetPreviewFrame = CGRectZero;
    
    if (animated) {
        // The target view won't be properly sized until we execute the lines above.
        if (CGRectIsEmpty(toViewRect))
            toViewRect = toView.bounds;
        if (CGRectIsEmpty(fromViewRect))
            fromViewRect = fromView.bounds;
        
        sourcePreviewFrame = [fromView convertRect:fromViewRect toView:view];
        targetPreviewFrame = [toView convertRect:toViewRect toView:view];
      
        // Old code to make sure that we zoomed w/o stretching the preview/content to an incorrect aspect ratio. But we should ensure that our preview images have the right aspect ratio now.
#if 0
        if (targetPreviewFrame.size.width > sourcePreviewFrame.size.width)
            targetPreviewFrame.size.height = targetPreviewFrame.size.width * (sourcePreviewFrame.size.height / sourcePreviewFrame.size.width);
        else
            sourcePreviewFrame.size.height = sourcePreviewFrame.size.width * (targetPreviewFrame.size.height / targetPreviewFrame.size.width);
#endif
        
        // If we are zoomed way in, this animation isn't going to look great and we'll end up crashing trying to build a static image anyway.
        {
            CGRect bounds = view.bounds;
            
            if (sourcePreviewFrame.size.width > 2 * bounds.size.width ||
                sourcePreviewFrame.size.height > 2 * bounds.size.height ||
                targetPreviewFrame.size.width > 2 * bounds.size.width ||
                targetPreviewFrame.size.height > 2 * bounds.size.height)
                animated = NO;
        }
    }
    
    _OUIMainViewControllerTransitionView *transitionView = nil;
    
    NSTimeInterval duration = 0;
    if (animated) {
        duration = 0.3;
        transitionView = [[_OUIMainViewControllerTransitionView alloc] initWithFromView:fromView toView:toView sourcePreviewFrame:sourcePreviewFrame];
        [view addSubview:transitionView];
        
        // The 'to' and from views while animating the transition view.
        viewController.view.hidden = YES;
        fromView.hidden = YES;

        MAIN_VC_DEBUG(@"  sourcePreviewFrame = %@", NSStringFromCGRect(sourcePreviewFrame));
        MAIN_VC_DEBUG(@"  targetPreviewFrame = %@", NSStringFromCGRect(targetPreviewFrame));
    }
        
        
    // Make sure that if any views in the old inner view controller have been sent -setNeedsDisplay that they won't start trying to fill their layers as the CoreAnimation loop starts running. They are dead!
    // Might have been unloaded already -- don't provoke a reload.
    if ([_innerViewController isViewLoaded]) {
        OBASSERT(_innerViewController.view.superview == backgroundView.contentView);
        MAIN_VC_DEBUG(@"remove subview for %@", [_innerViewController shortDescription]);
        [_innerViewController.view removeFromSuperview];
    }
    
    [OUIAnimationSequence runWithDuration:duration actions:
     ^{
         [transitionView transitionToFrame:targetPreviewFrame];
         
//         if (animated)
//             [backgroundView.toolbar setItems:viewController.toolbarItems animated:YES]; // Otherwise done in the next block

     },
     [NSNumber numberWithDouble:0.0], // Stop animating for last block
     ^{
         OBASSERT([UIView areAnimationsEnabled] == NO);

         if (_innerViewController) {
             MAIN_VC_DEBUG(@"removeFromParentViewController for old inner view %@", [_innerViewController shortDescription]);
             [_innerViewController removeFromParentViewController]; // Sends -didMoveToParentViewController:
             [_innerViewController release];
             _innerViewController = nil;
         }
         
         if (viewController) {
             _innerViewController = [viewController retain];

             MAIN_VC_DEBUG(@"add subview for %@", [_innerViewController shortDescription]);
             [backgroundView.contentView addSubview:_innerViewController.view];
             backgroundView.toolbar = [_innerViewController toolbarForMainViewController];

             [backgroundView.contentView layoutIfNeeded];
             viewController.view.hidden = NO;
//             if (!animated)
//                 [backgroundView.toolbar setItems:_innerViewController.toolbarItems animated:NO]; // Otherwise done in the previous block
             backgroundView.editing = _innerViewController.isEditingViewController;

             MAIN_VC_DEBUG(@"did-move-to for %@", [_innerViewController shortDescription]);
             [_innerViewController didMoveToParentViewController:self]; // -addChildViewController: doesn't call this, but does the 'will'
         }
         
         [transitionView removeFromSuperview];
         [transitionView release];
         
         // We hid this when animating, so put it back.
         OBASSERT(!animated || fromView.hidden == YES);
         fromView.hidden = NO;
         
         // In case someone claims they were going to do an animated switch but then does a non-animated one.
         [[OUIAppController controller] hideActivityIndicator];
     },
     nil];
}

- (void)setInnerViewController:(UIViewController *)viewController animated:(BOOL)animated fromView:(UIView *)fromView toView:(UIView *)toView;
{
    [self setInnerViewController:viewController animated:animated
                      fromRegion:^(UIView **outView, CGRect *outRect){
                          *outView = fromView;
                          *outRect = CGRectZero;
                      }
                        toRegion:^(UIView **outView, CGRect *outRect){
                            *outView = toView;
                            *outRect = CGRectZero;
                        }
                transitionAction:nil];
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

NSString * const OUIMainViewControllerResizedForKeyboard = @"OUIMainViewControllerResizedForKeyboard";
NSString * const OUIMainViewControllerResizedForKeyboardVisibilityKey = @"visibility";
NSString * const OUIMainViewControllerResizedForKeyboardOriginalUserInfoKey = @"originalInfo";

static void _postVisibility(OUIMainViewController *self, BOOL visibility, NSDictionary *originalInfo)
{
    NSDictionary *userInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
                              visibility ? (id)kCFBooleanTrue : (id)kCFBooleanFalse, OUIMainViewControllerResizedForKeyboardVisibilityKey,
                              originalInfo, OUIMainViewControllerResizedForKeyboardOriginalUserInfoKey,
                              nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIMainViewControllerResizedForKeyboard object:self userInfo:userInfo];
    [userInfo release];
}

- (void)keyboardWillShow:(NSNotification *)note;
{
    OBPRECONDITION([self isViewLoaded]);
    
    // Documentation, mail or other modal view atop us -- the keyboard isn't for us. This has an implicit assumption that the keyboard will go away before the modal view controller.
    if (self.modalViewController)
        return;
    
    // Resize our content view so that it isn't obscured by the keyboard. Our superview is the background view, who has the window as its superview. Window coordinates are in device space (unrotated), but our superview will have orientation correct coordinates. The keyboard will have device coordinates (unrotated).
    OUIMainViewControllerBackgroundView *backgroundView = (OUIMainViewControllerBackgroundView *)self.view;
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
        NSDictionary *userInfo = [note userInfo];
        
        // Match the keyboard animation time and curve. Also, starting from the current position is very important. If we don't and we are jumping between two editable controls, our view size may bounce.
        [UIView setAnimationDuration:[[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue]];
        [UIView setAnimationCurve:[[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];
        [UIView setAnimationBeginsFromCurrentState:YES];
        
        backgroundView.avoidedBottomHeight = avoidedBottomHeight;
        [backgroundView layoutIfNeeded]; // since our notification says we have resized

        _postVisibility(self, YES, userInfo);

        [backgroundView layoutIfNeeded]; // in case the notification moves anything else around
    }
    [UIView commitAnimations];

}

- (void)keyboardWillHide:(NSNotification *)note;
{
    OUIMainViewControllerBackgroundView *backgroundView = (OUIMainViewControllerBackgroundView *)self.view;
    NSDictionary *userInfo = [note userInfo];

    // Documentation, mail or other modal view atop us -- the keyboard isn't for us. This has an implicit assumption that the keyboard will go away before the modal view controller.
    // Still, if the keyboard is gone, we need to make clear our avoidance.
    if (self.modalViewController) {
        OUIWithoutAnimating(^{
            backgroundView.avoidedBottomHeight = 0;
            [backgroundView layoutIfNeeded];
            
            _postVisibility(self, NO, userInfo);
            [backgroundView layoutIfNeeded]; // in case the notification moves anything else around
        });
        return;
    }

    // Remove the restriction on the content height
    [UIView beginAnimations:@"done avoiding keyboard" context:NULL];
    {
        // Match the keyboard animation time and curve. Also, starting from the current position is very important. If we don't and we are jumping between two editable controls, our view size may bounce.
        [UIView setAnimationDuration:[[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue]];
        [UIView setAnimationCurve:[[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue]];
        [UIView setAnimationBeginsFromCurrentState:YES];

        backgroundView.avoidedBottomHeight = 0;
        [backgroundView layoutIfNeeded];

        _postVisibility(self, NO, userInfo);
        [backgroundView layoutIfNeeded]; // in case the notification moves anything else around
    }
    [UIView commitAnimations];
}

- (void)resetToolbarFromMainViewController;
{
    OUIMainViewControllerBackgroundView *view = (OUIMainViewControllerBackgroundView *)self.view;
    view.toolbar = [_innerViewController toolbarForMainViewController];
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
    
    OUIMainViewControllerBackgroundView *view = [[OUIMainViewControllerBackgroundView alloc] initWithFrame:CGRectMake(0, 0, kStartingSize, kStartingSize)];
    [self setView:view]; // Have to do this before calling down into code that might as for our view

    // If there was a low memory warning and we were off screen during it (full screen modal view up), we might actually be getting called for the second time.
    if (_innerViewController) {
        [self adjustSizeToMatch:_innerViewController];
        
        [view.contentView addSubview:_innerViewController.view];
        view.toolbar = [_innerViewController toolbarForMainViewController];
        
        //[view.toolbar setItems:_innerViewController.toolbarItems animated:NO];
    }

    [view release];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
{
    return YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation;
{
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
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

// UIViewController (OUIMainViewControllerExtensions) -- Use iOS 5 view containment methods instead
OBDEPRECATED_METHOD(-willResignInnerToolbarController:animated:);
OBDEPRECATED_METHOD(-didResignInnerToolbarController:);
OBDEPRECATED_METHOD(-willBecomeInnerToolbarController:animated:);
OBDEPRECATED_METHOD(-didBecomeInnerToolbarController:);
OBDEPRECATED_METHOD(-prepareToResignInnerToolbarController:);
OBDEPRECATED_METHOD(-prepareToResignInnerToolbarControllerAndReturnParentViewForActivityIndicator:);


@implementation UIViewController (OUIMainViewControllerExtensions)

- (UIToolbar *)toolbarForMainViewController;
{
    return nil;
}

- (BOOL)isEditingViewController;
{
    return YES;
}
@end
