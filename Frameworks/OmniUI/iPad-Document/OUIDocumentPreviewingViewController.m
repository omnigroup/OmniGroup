// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPreviewingViewController.h>

#import <OmniDocumentStore/ODSFileItem.h>

#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUIDocument/OUIDocumentPreviewView.h>

RCS_ID("$Id$");

@interface OUIDocumentPreviewingViewController () <UINavigationBarDelegate>

@property (nonatomic, strong, readwrite) ODSFileItem *fileItem;
@property (nonatomic, strong) OUIDocumentPreview *preview;

@property (weak, nonatomic) IBOutlet UINavigationBar *navBar;
@property (weak, nonatomic) IBOutlet UIView *containerView;
@property (weak, nonatomic) IBOutlet OUIDocumentPreviewView *previewView;
@property (weak, nonatomic) IBOutlet UIView *documentInfoContainerView;
@property (weak, nonatomic) IBOutlet UILabel *documentNameLabel;
@property (weak, nonatomic) IBOutlet UILabel *documentUserModifiedDateLabel;

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *navBarHeightConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *containerViewTopConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *containerViewTrailingConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *containerViewLeadingConstraint;

@end

@implementation OUIDocumentPreviewingViewController

- (instancetype)initWithFileItem:(ODSFileItem *)fileItem preview:(OUIDocumentPreview *)preview;
{
    self = [super initWithNibName:@"OUIDocumentPreviewingViewController" bundle:OMNI_BUNDLE];
    if (self != nil) {
        _fileItem = fileItem;
        _preview = preview;
    }
    
    return self;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    // Need to be pinned to the topLayoutGude so we get the automatic 64pt high nav bar that goes under the status bar.
    [NSLayoutConstraint constraintWithItem:self.navBar attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual
                                    toItem:self.topLayoutGuide attribute:NSLayoutAttributeBottom
                                multiplier:1.0
                                  constant:0.0].active = YES;
    
    self.navBar.delegate = self;
    self.navBarHeightConstraint.constant = 0.0;
    
    self.previewView.preview = self.preview;
    
    self.documentNameLabel.text = self.fileItem.name;
    self.documentUserModifiedDateLabel.text = [self _userModificationStringFromDate:self.fileItem.userModificationDate];
}

- (void)viewDidLayoutSubviews;
{
    // For peek, we only get to set the width or the height, depending on if we are in portrait or landscape. (For portrait we get to se the height; For landscape, the width.)
    CGFloat documentInfoHeight = [self.documentInfoContainerView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
    
    UIWindow *window = [UIApplication sharedApplication].delegate.window;
    CGSize windowSize = window.bounds.size;
    if (windowSize.width > windowSize.height) {
        // Landscape, set the width.
        self.preferredContentSize = (CGSize){
            .width = windowSize.height - documentInfoHeight,
            .height = 0
        };
    } else {
        // Portrait, set the height.
        self.preferredContentSize = (CGSize){
            .width = 0,
            .height = windowSize.width + documentInfoHeight
        };
    }
    
    [super viewDidLayoutSubviews];
}

- (UIView *)backgroundSnapshotView;
{
    self.containerView.hidden = YES;
    UIView *bg = [self.view snapshotViewAfterScreenUpdates:YES];
    self.containerView.hidden = NO;
    return bg;
}

- (UIView *)previewSnapshotView;
{
    return [self.previewView snapshotViewAfterScreenUpdates:NO];
}

- (CGRect)previewRect;
{
    CGRect pr = [self.previewView.superview convertRect:self.previewView.frame toView:nil];
    return pr;
}

- (void)prepareForCommitWithBackgroundView:(UIView *)backgroundView;
{
    self.navBarHeightConstraint.constant = 44.0;
    self.documentInfoContainerView.hidden = YES;
    
    if (backgroundView != nil) {
        [self.view addSubview:backgroundView];
        [self.view sendSubviewToBack:backgroundView];
        
        [backgroundView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
        [backgroundView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;
        [backgroundView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
        [backgroundView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
        
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        UIVisualEffectView *visualEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        visualEffectView.translatesAutoresizingMaskIntoConstraints = NO;
        
        [self.view insertSubview:visualEffectView aboveSubview:backgroundView];
        
        [visualEffectView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
        [visualEffectView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor].active = YES;
        [visualEffectView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
        [visualEffectView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor].active = YES;
    }
    
    UIWindow *window = [UIApplication sharedApplication].delegate.window;
    CGSize windowSize = window.bounds.size;
    if (windowSize.width > windowSize.height) {
        // Landscape
        CGFloat topPadding = 10.0;
        self.containerViewTopConstraint.constant = topPadding;
    }
    else {
        // Portrait
        CGFloat leftRightPadding = 8.0;
        self.containerViewLeadingConstraint.constant = leftRightPadding;
        self.containerViewTrailingConstraint.constant = leftRightPadding;
    }
}

#pragma mark Private API
- (NSString *)_userModificationStringFromDate:(NSDate *)date;
{
    static NSDateFormatter *formatter = nil;
    if (!formatter) {
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterLongStyle;
        formatter.timeStyle = NSDateFormatterNoStyle;
    }
    NSString *dateString = [formatter stringFromDate:date];
    return dateString;
}

#pragma mark UINavigationBarDelegate <UIBarPositioningDelegate>
- (UIBarPosition)positionForBar:(id <UIBarPositioning>)bar;
{
    if (bar == self.navBar) {
        return UIBarPositionTopAttached;
    }
    else {
        return UIBarPositionAny;
    }
}

@end
