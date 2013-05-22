// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIMainViewController.h>

#import "OUIDocumentParameters.h"

#import <OmniFoundation/OFExtent.h>
#import <OmniFoundation/OFVersionNumber.h>
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

#if 0 && defined(DEBUG)
    #define DEBUG_KEYBOARD(format, ...) NSLog(@"KEYBOARD: " format, ## __VA_ARGS__)
#else
    #define DEBUG_KEYBOARD(format, ...)
#endif

@interface _OUIMainViewControllerTransitionView : UIView
- initWithFromImage:(UIImage *)fromImage toImage:(UIImage *)toImage sourceFrame:(CGRect)sourceFrame;
- initWithFromView:(UIView *)fromView toView:(UIView *)toView sourceFrame:(CGRect)sourceFrame;
- (void)transitionToFrame:(CGRect)targetPreviewFrame;
#ifdef DEBUG
- (void)writeImagesWithPrefix:(NSString *)prefix;
#endif
@end

@implementation _OUIMainViewControllerTransitionView
{
    UIImage *_fromImage;
    UIImage *_toImage;
    UIView *_innerSnapshotView;
}

- initWithFromImage:(UIImage *)fromImage toImage:(UIImage *)toImage sourceFrame:(CGRect)sourceFrame;
{
    OBPRECONDITION(fromImage);
    OBPRECONDITION(toImage);
    
    if (!(self = [super initWithFrame:sourceFrame]))
        return nil;
    
    // We want our transition views above all other peer views.
    self.layer.zPosition = 1;
    
    _fromImage = fromImage;
    _toImage = toImage;
    
    // We'll use this view to fade in the new image.
    _innerSnapshotView = [[UIView alloc] initWithFrame:self.bounds];
    [self addSubview:_innerSnapshotView];
    
    self.layer.contents = (id)[_fromImage CGImage];
    self.layer.contentsGravity = kCAGravityResize;
    
    _innerSnapshotView.layer.contents = (id)[_toImage CGImage];
    _innerSnapshotView.layer.contentsGravity = kCAGravityResize;
    _innerSnapshotView.alpha = 0;
    
    return self;
}

- initWithFromView:(UIView *)fromView toView:(UIView *)toView sourceFrame:(CGRect)sourceFrame;
{
    return [self initWithFromImage:[fromView snapshotImage]
                           toImage:[toView snapshotImage]
                       sourceFrame:sourceFrame];
}

- (void)transitionToFrame:(CGRect)targetPreviewFrame;
{
    self.frame = targetPreviewFrame;
    
    _innerSnapshotView.frame = self.bounds;
    _innerSnapshotView.alpha = 1;
}

#ifdef DEBUG
- (void)writeImagesWithPrefix:(NSString *)prefix;
{
    __autoreleasing NSError *error = nil;
    
    NSString *fromPath = [NSString stringWithFormat:@"~/tmp/%@-from.png", prefix];
    if (![UIImagePNGRepresentation(_fromImage) writeToFile:[fromPath stringByExpandingTildeInPath] options:0 error:&error])
        NSLog(@"Unable to write PNG to \"%@\": %@", fromPath, [error toPropertyList]);
    
    NSString *toPath = [NSString stringWithFormat:@"~/tmp/%@-to.png", prefix];
    if (![UIImagePNGRepresentation(_toImage) writeToFile:[toPath stringByExpandingTildeInPath] options:0 error:&error])
        NSLog(@"Unable to write PNG to \"%@\": %@", toPath, [error toPropertyList]);
}
#endif


@end

@implementation OUIMainViewController
{
    CGFloat _lastKeyboardHeight;
    UIViewController *_innerViewController;
    BOOL _resizesToAvoidKeyboard;
    BOOL _ignoringInteractionWhileAnimatingToAvoidKeyboard; // We ignore events at the application level while resizing to avoid the keyboard
    BOOL _keyboardInititallyShowing;
    
    NSUInteger _interactionIgnoreCount;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
              transitionAction:(void (^)(void))transitionAction
              completionAction:(void (^)(void))completionAction;
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

    // Tell the background which image it should display for the new controller.
    OUIMainViewControllerBackgroundView *mainView = (OUIMainViewControllerBackgroundView *)self.view;
    
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
    [mainView.contentView addSubview:viewController.view];
    
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
        fromView = fromRegion(&fromViewRect);
    if (toRegion)
        toView = toRegion(&toViewRect);
    
    if (!fromView)
        fromView = _innerViewController.view;
    if (!toView)
        toView = viewController.view;
    
    MAIN_VC_DEBUG(@"  fromView %@", [fromView shortDescription]);
    MAIN_VC_DEBUG(@"  fromViewRect %@", NSStringFromCGRect(fromViewRect));
    MAIN_VC_DEBUG(@"  toView %@", [toView shortDescription]);
    MAIN_VC_DEBUG(@"  toViewRect %@", NSStringFromCGRect(toViewRect));

    OBASSERT((!fromView && !animated) || [fromView isDescendantOfView:_innerViewController.view]); // First setup with have no old view controller and shouldn't be animated
    OBASSERT([toView isDescendantOfView:viewController.view]);
    
    // We'll be hiding these views while animating; shouldn't be hidden yet.
    OBASSERT(fromView.layer.hidden == NO);
    OBASSERT(toView.layer.hidden == NO);
    
    CGRect sourcePreviewFrame = CGRectZero;
    CGRect targetPreviewFrame = CGRectZero;
    
    if (animated) {
        // The target view won't be properly sized until we execute the lines above.
        if (CGRectIsEmpty(toViewRect))
            toViewRect = toView.bounds;
        if (CGRectIsEmpty(fromViewRect))
            fromViewRect = fromView.bounds;
        
        sourcePreviewFrame = [fromView convertRect:fromViewRect toView:mainView];
        targetPreviewFrame = [toView convertRect:toViewRect toView:mainView];
      
        // Old code to make sure that we zoomed w/o stretching the preview/content to an incorrect aspect ratio. But we should ensure that our preview images have the right aspect ratio now.
#if 0
        if (targetPreviewFrame.size.width > sourcePreviewFrame.size.width)
            targetPreviewFrame.size.height = targetPreviewFrame.size.width * (sourcePreviewFrame.size.height / sourcePreviewFrame.size.width);
        else
            sourcePreviewFrame.size.height = sourcePreviewFrame.size.width * (targetPreviewFrame.size.height / targetPreviewFrame.size.width);
#endif
        
        // If we are zoomed way in, this animation isn't going to look great and we'll end up crashing trying to build a static image anyway.
        {
            CGRect bounds = mainView.bounds;
            
            if (sourcePreviewFrame.size.width > 2 * bounds.size.width ||
                sourcePreviewFrame.size.height > 2 * bounds.size.height ||
                targetPreviewFrame.size.width > 2 * bounds.size.width ||
                targetPreviewFrame.size.height > 2 * bounds.size.height)
                animated = NO;
        }
    }
    
    _OUIMainViewControllerTransitionView *foregroundTransitionView = nil;
    _OUIMainViewControllerTransitionView *backgroundTransitionView = nil;
    UIImage *backgroundFromImage = nil;
    BOOL toViewHasBackground = YES;
    
    NSTimeInterval duration = 0;
    if (animated) {
        duration = 0.3;
        foregroundTransitionView = [[_OUIMainViewControllerTransitionView alloc] initWithFromView:fromView toView:toView sourceFrame:sourcePreviewFrame];
        
        // Hide the 'to' and 'from' views while animating the transition view.
        toView.hidden = YES;
        fromView.hidden = YES;

        // Capture the entire rest of the view hierarchy (including the toolbar and background view) for the "from" state.
        // There might not be a foreground/background difference in the destination, though. In this case, we need to leave the destination view hidden until the animation is complete.
        toViewHasBackground = (viewController.view != toView);
        
        OBASSERT(viewController.view.hidden == NO || !toViewHasBackground);

        if (toViewHasBackground)
            viewController.view.hidden = YES;
        
        backgroundFromImage = [mainView snapshotImage];
        
        if (toViewHasBackground)
            viewController.view.hidden = NO;

        MAIN_VC_DEBUG(@"  sourcePreviewFrame = %@ (window: %@)", NSStringFromCGRect(sourcePreviewFrame), NSStringFromCGRect([mainView convertRect:sourcePreviewFrame toView:mainView.window]));
        MAIN_VC_DEBUG(@"  targetPreviewFrame = %@ (window: %@)", NSStringFromCGRect(targetPreviewFrame), NSStringFromCGRect([mainView convertRect:targetPreviewFrame toView:mainView.window]));
        
#if 0 && defined(DEBUG)
        [foregroundTransitionView writeImagesWithPrefix:@"foreground"];
#endif
    }

    // Set up the pattern the background view should use and the new toolbar (this happens between capturing the two background transition images so that the toolbar will be included in the background dissolve).
    OUIWithoutAnimating(^{
        mainView.editing = viewController.isEditingViewController;
        mainView.toolbar = [viewController toolbarForMainViewController];
    });

    // Make sure that if any views in the old inner view controller have been sent -setNeedsDisplay that they won't start trying to fill their layers as the CoreAnimation loop starts running. This view has been told to go away and might be referencing data that is invalid or that could become invalid soon (seems less likely now that we have UIDocument asynchronous closing, though).
    // Might have been unloaded already -- don't provoke a reload.
    if ([_innerViewController isViewLoaded]) {
        OBASSERT(_innerViewController.view.superview == mainView.contentView);
        MAIN_VC_DEBUG(@"remove subview for %@", [_innerViewController shortDescription]);
        [_innerViewController.view removeFromSuperview];
    }
    
    if (animated) {
        // Now capture the 'to' background image and add the background transition view        
        backgroundTransitionView = [[_OUIMainViewControllerTransitionView alloc] initWithFromImage:backgroundFromImage toImage:[mainView snapshotImage] sourceFrame:mainView.bounds];
                
        // Add the two transition views after all the capturing is done (don't want to polute one transition with the other's starting or ending image).
        [mainView addSubview:foregroundTransitionView];
        [mainView insertSubview:backgroundTransitionView belowSubview:foregroundTransitionView];
        
#if 0 && defined(DEBUG)
        [backgroundTransitionView writeImagesWithPrefix:@"background"];
#endif
    }
    
    // Need to capture scope for this block since call it after firing up the animation and returning from this method
    completionAction = [completionAction copy];
    
    [OUIAnimationSequence runWithDuration:duration actions:
     ^{
         [foregroundTransitionView transitionToFrame:targetPreviewFrame];
         [backgroundTransitionView transitionToFrame:mainView.bounds];
     },
     ^{
         OUIWithoutAnimating(^{
             if (_innerViewController) {
                 MAIN_VC_DEBUG(@"removeFromParentViewController for old inner view %@", [_innerViewController shortDescription]);
                 [_innerViewController removeFromParentViewController]; // Sends -didMoveToParentViewController:
                 _innerViewController = nil;
             }
             
             if (viewController) {
                 _innerViewController = viewController;
                 
                 MAIN_VC_DEBUG(@"add subview for %@", [_innerViewController shortDescription]);
                 [mainView.contentView addSubview:_innerViewController.view];                 
                 [mainView.contentView layoutIfNeeded];
                 
                 MAIN_VC_DEBUG(@"did-move-to for %@", [_innerViewController shortDescription]);
                 [_innerViewController didMoveToParentViewController:self]; // -addChildViewController: doesn't call this, but does the 'will'
             }
             
             [foregroundTransitionView removeFromSuperview];
             
             [backgroundTransitionView removeFromSuperview];
             
             // We may have hidden these when animating
             fromView.hidden = NO;
             toView.hidden = NO;
         });
         
         // Let VoiceOver know the entire screen has changed.
         UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
         
         if (completionAction)
             completionAction();
     },
     nil];
}

- (void)setInnerViewController:(UIViewController *)viewController animated:(BOOL)animated fromView:(UIView *)fromView toView:(UIView *)toView;
{
    [self setInnerViewController:viewController animated:animated
                      fromRegion:^UIView *(CGRect *outRect){
                          *outRect = CGRectZero;
                          return fromView;
                      }
                        toRegion:^UIView *(CGRect *outRect){
                            *outRect = CGRectZero;
                            return toView;
                        }
                transitionAction:nil completionAction:nil];
}

@synthesize resizesToAvoidKeyboard = _resizesToAvoidKeyboard;
- (void)setResizesToAvoidKeyboard:(BOOL)resizesToAvoidKeyboard;
{
    if (_resizesToAvoidKeyboard == resizesToAvoidKeyboard)
        return;
    _resizesToAvoidKeyboard = resizesToAvoidKeyboard;
    
    // NOTE! The show/hide notifications from the keyboard system are pretty useless since a device rotation causes a hide/show storm rather than just a frame change.
    // But also note we need them on < 5.1 due to a bug in 5.0.x
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (resizesToAvoidKeyboard) {
        [center addObserver:self selector:@selector(_keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(_keyboardDidChangeFrame:) name:UIKeyboardDidChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(_keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
        [center addObserver:self selector:@selector(_keyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    } else {
        [center removeObserver:self name:UIKeyboardWillChangeFrameNotification object:nil];
        [center removeObserver:self name:UIKeyboardDidChangeFrameNotification object:nil];
        [center removeObserver:self name:UIKeyboardWillShowNotification object:nil];
        [center removeObserver:self name:UIKeyboardDidShowNotification object:nil];
    }
}

NSString * const OUIMainViewControllerDidBeginResizingForKeyboard = @"OUIMainViewControllerDidBeginResizingForKeyboard";
NSString * const OUIMainViewControllerDidFinishResizingForKeyboard = @"OUIMainViewControllerDidFinishResizingForKeyboard";
NSString * const OUIMainViewControllerResizedForKeyboardOriginalUserInfoKey = @"originalInfo";

static void _postResize(OUIMainViewController *self, NSString *notificationName, NSDictionary *originalInfo)
{
    NSDictionary *userInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
                              originalInfo, OUIMainViewControllerResizedForKeyboardOriginalUserInfoKey,
                              nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:self userInfo:userInfo];
}

/*
 Notes on split/undocked keyboards:
 
 When transitioning between a normal software keyboard and a split/undocked keyboard, we'll get a UIKeyboardWillChangeFrameNotification with *just* UIKeyboardFrameBeginUserInfoKey and then a UIKeyboardDidChangeFrameNotification with just UIKeyboardFrameEndUserInfoKey. In this case, the keyboard really isn't involved in the animation of the content and doesn't send animation parameters.
 
 The one annoying part of this is that we going back to a docked state, we can't tell in the "will change" notification what the ending frame will be. So, we have the need to start an animation in our "did change" hook and have our own completion support for calling our did.

 */

static CGFloat _bottomHeightToAvoidForEndingKeyboardFrame(OUIMainViewController *self, NSNotification *note)
{
    OUIMainViewControllerBackgroundView *backgroundView = (OUIMainViewControllerBackgroundView *)self.view;
    OBASSERT(backgroundView.superview == backgroundView.window);
    
    // We should be directly in the window and taking up the whole application-available frame.
    CGRect appSpaceInBounds = [backgroundView convertRect:backgroundView.window.screen.applicationFrame fromView:nil];
    //NSLog(@"appSpaceInBounds %@", NSStringFromRect(appSpaceInBounds));
    
    NSValue *keyboardEndFrameValue = [[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey];
    if (keyboardEndFrameValue == nil) {
        DEBUG_KEYBOARD("  using full height due to missing end frame");
        return 0; // The user is starting a drag of the split keyboard.
    }

    CGRect keyboardRectInBounds = [backgroundView convertRect:[keyboardEndFrameValue CGRectValue] fromView:nil];
    //NSLog(@"keyboardRectInBounds = %@", NSStringFromRect(keyboardRectInBounds));
    
    OFExtent appSpaceYExtent = OFExtentFromRectYRange(appSpaceInBounds);
    OFExtent keyboardYExtent = OFExtentFromRectYRange(keyboardRectInBounds);
    
    DEBUG_KEYBOARD(@"app %@, keyboard %@", OFExtentToString(appSpaceYExtent), OFExtentToString(keyboardYExtent));
    
    // If the keyboard is all the way at the max-y end, then we can use our avoidance. Otherwise, it is split or undocked or something else weird may be going on. There is no good API for us to tell for sure.
    // We can still get a split keyboard with all the user info keys set if we start editing with the keyboard having previously been left in the split state.
    if (OFExtentMax(keyboardYExtent) < OFExtentMax(appSpaceYExtent)) {
        DEBUG_KEYBOARD("  using full height due to keyboard not reaching bottom of screen (%f vs %f)", OFExtentMax(keyboardYExtent), OFExtentMax(appSpaceYExtent));
        return 0;
    }
    
    // We get notified of the keyboard appearing, but with it fully off screen if the hardware keyboard is enabled. If we don't need to adjust anything, bail.
    if (!CGRectIntersectsRect(appSpaceInBounds, keyboardRectInBounds)) {
        DEBUG_KEYBOARD("  using full height due to keyboard being fully off screen");
        return 0;
    }
    
    // The keyboard will come up out of the bottom. Trim our height so that our max-y avoids it.
    // Since we can get multiple 'will show' notifications w/o a 'will hide' (when changing international keyboards changes the keyboard height), we can't assume that the contentView's height is the full unmodified height.
    CGFloat avoidedBottomHeight = CGRectGetMaxY(backgroundView.bounds) - CGRectGetMinY(keyboardRectInBounds);
    DEBUG_KEYBOARD("  avoiding bottom height of %f", avoidedBottomHeight);
    return avoidedBottomHeight;
}

- (BOOL)_handleKeyboardFrameChange:(NSNotification *)note isDid:(BOOL)isDid;
{
    OBPRECONDITION([self isViewLoaded]);
    
    // Resize our content view so that it isn't obscured by the keyboard. Our superview is the background view, who has the window as its superview. Window coordinates are in device space (unrotated), but our superview will have orientation correct coordinates. The keyboard will have device coordinates (unrotated).
    OUIMainViewControllerBackgroundView *backgroundView = (OUIMainViewControllerBackgroundView *)self.view;
    OBASSERT(backgroundView.superview == backgroundView.window);

    CGFloat avoidedBottomHeight = _bottomHeightToAvoidForEndingKeyboardFrame(self, note);
    
    if (_lastKeyboardHeight == avoidedBottomHeight) {
        DEBUG_KEYBOARD("  same (%f) -- bailing", _lastKeyboardHeight);
        return NO; // No animation started
    }
    
    _lastKeyboardHeight = avoidedBottomHeight;
    
    NSDictionary *userInfo = [note userInfo];
    
    if (self.presentedViewController) {
        // Documentation, mail or other modal view atop us -- the keyboard isn't for us. This has an implicit assumption that the keyboard will go away before the modal view controller.
        OUIWithoutAnimating(^{
            backgroundView.avoidedBottomHeight = avoidedBottomHeight;
            [backgroundView layoutIfNeeded];
            
            _postResize(self, OUIMainViewControllerDidBeginResizingForKeyboard, userInfo);
            [backgroundView layoutIfNeeded]; // in case the notification moves anything else around
        });
        return NO;
    } else {
        NSNumber *durationNumber = [userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey];
        NSNumber *curveNumber = [userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey];
        BOOL keyboardControllingAnimation = YES;
        
        // If specified, match the keyboard animation time and curve. We should get both or neither -- if we get neither, make up our own parameters and pass that along so clients don't have to guess what to do.
        if (!durationNumber || !curveNumber) {
            OBASSERT((durationNumber == nil) == (curveNumber == nil));
            durationNumber = [NSNumber numberWithDouble:0.25];
            curveNumber = [NSNumber numberWithInt:UIViewAnimationCurveEaseInOut];
            
            NSMutableDictionary *updatedInfo = [[NSMutableDictionary alloc] initWithDictionary:userInfo];
            [updatedInfo setObject:durationNumber forKey:UIKeyboardAnimationDurationUserInfoKey];
            [updatedInfo setObject:curveNumber forKey:UIKeyboardAnimationCurveUserInfoKey];
            
            userInfo = [updatedInfo copy];
            
            keyboardControllingAnimation = NO;
            DEBUG_KEYBOARD("keyboard not controlling animation");
        }

        // Ignore all events while the keyboard animation is going on so that double-taps on editable fields that will be covered by the keyboard don't hit a key on the second tap.
        // We can't just use our method since that only ignores events w/in our view, since that doesn't cover the keyboard. Also, the keyboard is immediately in place after the 'will' as far as hit testing goes, so the second tap can actually hit it before it is done animating to that spot.
        if (_ignoringInteractionWhileAnimatingToAvoidKeyboard == NO && _keyboardInititallyShowing) {
            DEBUG_KEYBOARD("disabling interaction during initial keyboard animation");
            _ignoringInteractionWhileAnimatingToAvoidKeyboard = YES;
            [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
        }
        
        void (^completionHandler)(BOOL finished) = nil;
        if (isDid && !keyboardControllingAnimation) {
            // The UIKit keyboard won't be animating for us and we're starting an animation in the 'did' but sending OUIMainViewControllerDidBeginResizingForKeyboard. Wait for *our* animation to finish and send the OUIMainViewControllerDidFinishResizingForKeyboard.
            DEBUG_KEYBOARD("will post did-finish");
            completionHandler = ^(BOOL finished){
                
                if (_ignoringInteractionWhileAnimatingToAvoidKeyboard) {
                    DEBUG_KEYBOARD("enabling interaction after keyboard animation");
                    _ignoringInteractionWhileAnimatingToAvoidKeyboard = NO;
                    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                }
                
                DEBUG_KEYBOARD("posting did-finish");
                _postResize(self, OUIMainViewControllerDidFinishResizingForKeyboard, userInfo);
            };
        }
        
        [UIView animateWithDuration:[durationNumber doubleValue] animations:
         ^{
             [UIView setAnimationCurve:[curveNumber intValue]];
             
             // Also, starting from the current position is very important. If we don't and we are jumping between two editable controls, our view size may bounce.
             [UIView setAnimationBeginsFromCurrentState:YES];
             
             backgroundView.avoidedBottomHeight = avoidedBottomHeight;
             [backgroundView layoutIfNeeded]; // since our notification says we have resized
             
             _postResize(self, OUIMainViewControllerDidBeginResizingForKeyboard, userInfo);
             
             [backgroundView layoutIfNeeded]; // in case the notification moves anything else around
         }
                         completion:completionHandler];
        
        return YES;
    }
}

- (void)_keyboardWillChangeFrame:(NSNotification *)note;
{
    DEBUG_KEYBOARD("will change frame %@", note);
    
    [self _handleKeyboardFrameChange:note isDid:NO];
}

- (void)_keyboardDidChangeFrame:(NSNotification *)note;
{
    DEBUG_KEYBOARD("did change frame %@", note);

    if ([self _handleKeyboardFrameChange:note isDid:YES]) {
        // Animation started from the did -- it will send the OUIMainViewControllerDidFinishResizingForKeyboard
    } else {
        if (_ignoringInteractionWhileAnimatingToAvoidKeyboard) {
            DEBUG_KEYBOARD("enabling interaction after keyboard animation");
            _ignoringInteractionWhileAnimatingToAvoidKeyboard = NO;
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        }

        // Otherwise they keyboard was driving the animation and it has finished, so we should do it now.
        NSDictionary *userInfo = [note userInfo];
        _postResize(self, OUIMainViewControllerDidFinishResizingForKeyboard, userInfo);
    }
}

// See note where we subscribe to UIKeyboardDidShowNotification
- (void)_keyboardWillShow:(NSNotification *)note;
{
    DEBUG_KEYBOARD("will show %@", note);
    _keyboardInititallyShowing = YES;
}

- (void)_keyboardDidShow:(NSNotification *)note;
{
    _keyboardInititallyShowing = NO;
    DEBUG_KEYBOARD("did show %@", note);
}

- (void)resetToolbarFromMainViewController;
{
    OUIMainViewControllerBackgroundView *view = (OUIMainViewControllerBackgroundView *)self.view;
    view.toolbar = [_innerViewController toolbarForMainViewController];
}

// Maintains a local counter and disables interaction on just this view controller's view and subviews (not the whole app)
- (void)beginIgnoringInteractionEvents;
{
    if (_interactionIgnoreCount == 0) {
        UIView *view = self.view;
        OBASSERT(view.userInteractionEnabled == YES); // No one else should twiddle this
        view.userInteractionEnabled = NO;
    }
    _interactionIgnoreCount++;
}

- (void)endIgnoringInteractionEvents;
{
    if (_interactionIgnoreCount == 0) {
        OBASSERT_NOT_REACHED("Mismatched -beginIgnoringInteractionEvents and -endIgnoringInteractionEvents?");
        OBASSERT(self.view.userInteractionEnabled == YES);
        return;
    }
    
    _interactionIgnoreCount--;
    if (_interactionIgnoreCount == 0) {
        UIView *view = self.view;
        OBASSERT(view.userInteractionEnabled == NO); // No one else should twiddle this
        view.userInteractionEnabled = YES;
    } else {
        OBASSERT(self.view.userInteractionEnabled == NO);
    }
}

#pragma mark - UIViewController (OUIScalingScrollView)

- (CGRect)contentViewFullScreenBounds;
{
    OUIMainViewControllerBackgroundView *view = (OUIMainViewControllerBackgroundView *)self.view;
    return [view contentViewFullScreenBounds];
}

#pragma mark - UIViewController subclass

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

}

- (BOOL)shouldAutorotate;
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
    // We want to ensure that we don't get an implicitly created undo manager (OUIDocument/OUIDocumentAppController have other assertions to make sure that only the document's undo manager is used).
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

- (UIColor *)activityIndicatorColorForMainViewController;
{
    return nil;
}

@end
