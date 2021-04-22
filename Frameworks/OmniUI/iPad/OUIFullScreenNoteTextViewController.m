// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIFullScreenNoteTextViewController.h>

#import <OmniUI/OUINoteTextView.h>
#import <OmniUI/OUIKeyboardNotifier.h>
#import <OmniUI/UIView-OUIExtensions.h>

@implementation OUIFullScreenNoteTextViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:@"OUIFullScreenNoteTextView" bundle:OMNI_BUNDLE];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.selectedRange = NSMakeRange(NSNotFound, 0);
        self.viewRespectsSystemMinimumLayoutMargins = NO;
    }
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIKeyboardNotifierKeyboardWillChangeFrameNotification object:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.view.tintAdjustmentMode = UIViewTintAdjustmentModeNormal;

    UINavigationItem *navigationItem = self.fullScreenNavigationBar.topItem;
    navigationItem.title = NSLocalizedStringFromTableInBundle(@"Note", @"OmniUI", OMNI_BUNDLE, @"Full screen note editor title");
    navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(exitFullScreen:)];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardHeightWillChange:) name:OUIKeyboardNotifierKeyboardWillChangeFrameNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];

    self.textView.text = self.text;
}

- (void)_keyboardHeightWillChange:(NSNotification *)keyboardNotification;
{
    OUIKeyboardNotifier *notifier = [OUIKeyboardNotifier sharedNotifier];
    UIEdgeInsets insets = self.textView.contentInset;
    insets.bottom = notifier.lastKnownKeyboardHeight;
    [UIView animateWithDuration:notifier.lastAnimationDuration delay:0 options:OUIAnimationOptionFromCurve(notifier.lastAnimationCurve) animations:^{
        self.textView.contentInset = insets;
    } completion:nil];
}

- (IBAction)exitFullScreen:(id)sender;
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^() {
        if (self.dismissedCompletionHandler)
            self.dismissedCompletionHandler(self);
    }];
}

@end
