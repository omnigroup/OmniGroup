// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIFullScreenNoteTextViewController.h>

#import <OmniUI/OUINoteTextView.h>

RCS_ID("$Id$")

@implementation OUIFullScreenNoteTextViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:@"OUIFullScreenNoteTextView" bundle:OMNI_BUNDLE];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.selectedRange = NSMakeRange(NSNotFound, 0);
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.view.tintAdjustmentMode = UIViewTintAdjustmentModeNormal;

    UINavigationItem *navigationItem = self.fullScreenNavigationBar.topItem;
    navigationItem.title = NSLocalizedStringFromTableInBundle(@"Note", @"OmniUI", OMNI_BUNDLE, @"Full screen note editor title");
    navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(exitFullScreen:)];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];

    self.textView.text = self.text;
}

- (IBAction)exitFullScreen:(id)sender;
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^() {
        if (self.dismissedCompletionHandler)
            self.dismissedCompletionHandler(self);
    }];
}

@end
