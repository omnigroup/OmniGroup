//
//  OUIFullScreenNoteTextViewController.m
//  OmniUI
//
//  Created by tom on 11/12/13.
//
//

#import "OUIFullScreenNoteTextViewController.h"

#import <OmniUI/OUINoteTextView.h>

@implementation OUIFullScreenNoteTextViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.selectedRange = NSMakeRange(NSNotFound, 0);
    }
    return self;
}

- (NSString *)nibName;
{
    return @"OUIFullScreenNoteTextView";
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
