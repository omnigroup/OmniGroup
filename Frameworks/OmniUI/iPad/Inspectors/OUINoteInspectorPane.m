// Copyright 2011-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUINoteInspectorPane.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIScalingTextStorage.h>
#import <OmniUI/OUINoteTextView.h>
#import <OmniUI/OUIFullScreenNoteTextViewController.h>
#import <OmniUI/OUIFullScreenNoteTransition.h>
#import <OmniUI/OUIKeyboardLock.h>
#import <OmniUI/OUIInspectorPresentationController.h>

RCS_ID("$Id$")

static const CGFloat EnterFullScreenButtonStandardAlpha = 0.25;
static const CGFloat EnterFullScreenButtonScrollingActiveAlpha = 0.4;

@interface OUINoteInspectorPane () <UIViewControllerTransitioningDelegate>

@end

@implementation OUINoteInspectorPane

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidChangeFrameNotification object:nil];
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.enterFullScreenButton.alpha = 0.0;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidChange:) name:UIKeyboardDidChangeFrameNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];

    // We can't ask for the presentationController before first knowing it's presented or the reciever will cacahe a presentationController until next present/dismiss cycle. This can result in the default full-screen presentation controller being cached if we havne't setup the transitioningDelegate yet.
    BOOL isCurrentlyPresented = (self.inspector.viewController.presentingViewController != nil);
    BOOL isUsingInspectorPresentationController = (isCurrentlyPresented && [self.inspector.viewController.presentationController isKindOfClass:[OUIInspectorPresentationController class]]);
    
    // If we're already fullscreen, no need for the enter full screen button
    if (self.view.window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact && isUsingInspectorPresentationController) {
        self.enterFullScreenButton.hidden = YES;
    } else {
        self.enterFullScreenButton.hidden = NO;
        self.enterFullScreenButton.alpha = EnterFullScreenButtonStandardAlpha; // fade in
    }

    // Larger left/right insets
    UIEdgeInsets insets = self.textView.textContainerInset;
    insets.left = 6.0;
    insets.right = 6.0;
    self.textView.textContainerInset = insets;
    
    [self.textView becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated;
{
    [super viewWillDisappear:animated];
    
    if ([self.textView isFirstResponder])
        [self applyChangesFromNoteTextView];
}

- (void)applyChangesFromNoteTextView;
{
    OBRequestConcreteImplementation(self, @selector(applyChangesFromNoteTextView));
}

- (void)keyboardDidChange:(NSNotification *)note;
{
    // Without some help here, UITextView doesn't redisplay exposed contents when the popover grows.
    OBFinishPortingLater("<bug:///147853> (iOS-OmniOutliner Bug: in landscape mode, when hiding the keyboard, long notes can end up with the bottom area not redrawn after the popover grows)");
    [self.view setNeedsLayout];
    [self.view setNeedsDisplay];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidEndEditing:(UITextView *)textView;
{
    [self applyChangesFromNoteTextView];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;
{
    [self setEnterFullScreenButtonAlpha:EnterFullScreenButtonScrollingActiveAlpha animated:YES];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;
{
    if (!decelerate)
        [self setEnterFullScreenButtonAlpha:EnterFullScreenButtonStandardAlpha animated:YES];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;
{
    [self setEnterFullScreenButtonAlpha:EnterFullScreenButtonStandardAlpha animated:YES];
}

#pragma mark -
#pragma mark Full Screen support

@synthesize enterFullScreenButton = _enterFullScreenButton;

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source;
{
    OUIFullScreenNoteTransition *transition = [[OUIFullScreenNoteTransition alloc] init];
    transition.fromTextView = self.textView;
    
    return transition;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed;
{
    OUIFullScreenNoteTransition *transition = [[OUIFullScreenNoteTransition alloc] init];
    transition.fromTextView = self.textView;
    
    return transition;
}

- (IBAction)enterFullScreen:(id)sender;
{
    OUIFullScreenNoteTextViewController *controller = [[OUIFullScreenNoteTextViewController alloc] init];
    
    controller.text = self.textView.text;
    controller.selectedRange = self.textView.selectedRange;
    controller.transitioningDelegate = self;
    controller.dismissedCompletionHandler = ^(OUIFullScreenNoteTextViewController *dismissedController) {
        self.textView.text = dismissedController.textView.text;
        if (self.textView.selectedRange.length)
            [self.textView becomeFirstResponder];
        else
            [self applyChangesFromNoteTextView];
    };
    controller.modalPresentationStyle = UIModalPresentationOverFullScreen;
    
    [controller loadViewIfNeeded];
    controller.textView.textColor = self.textView.textColor;
    controller.textView.backgroundColor = self.textView.backgroundColor;
    controller.textView.keyboardAppearance = self.textView.keyboardAppearance;

    [self presentViewController:controller animated:YES completion:^() {
    }];
    
}

- (void)setEnterFullScreenButtonAlpha:(CGFloat)alpha animated:(BOOL)animated;
{
    if (animated) {
        [UIView beginAnimations:@"AdjustEnterFullScreenButtonAlpha" context:NULL];
        [UIView setAnimationBeginsFromCurrentState:YES];
    }
    
    self.enterFullScreenButton.alpha = alpha;
    
    if (animated) {
        [UIView commitAnimations];
    }
}

@end

