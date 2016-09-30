// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentProviderPreferencesViewController.h>

#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$")

NSString * const OUIDocumentProviderPreferencesCloudDocumentsPreferenceTurnedOffNotification = @"OUIDocumentProviderPreferencesCloudDocumentsPreferenceTurnedOffNotification";

typedef NS_ENUM(NSUInteger, OUIDocumentProviderPreferencesSection) {
    OUIDocumentProviderPreferencesSectionSwitch,
    OUIDocumentProviderPreferencesSectionMoreInfo,
    OUIDocumentProviderPreferencesSectionCount
};

@interface OUIDocumentProviderPreferencesViewController ()
@property (weak, nonatomic) IBOutlet UILabel *shouldEnableDocumentProviderSwitchLabel;
@property (weak, nonatomic) IBOutlet UISwitch *shouldEnableDocumentProvidersSwitch;
@property (weak, nonatomic) IBOutlet UIButton *moreInfoButton;

- (IBAction)shouldEnableDocumentProvidersSwitchValueChanged:(id)sender;
- (IBAction)moreInfoButtonTapped:(id)sender;
@end

@implementation OUIDocumentProviderPreferencesViewController

+ (OUIDocumentProviderPreferencesViewController *)documentProviderPreferencesViewControllerFromStoryboard {
    UIStoryboard *sb = [UIStoryboard storyboardWithName:@"OUIDocumentProviderPreferences" bundle:OMNI_BUNDLE];
    UIViewController *vc = [sb instantiateInitialViewController];
    
    OBASSERT([vc isKindOfClass:[OUIDocumentProviderPreferencesViewController class]]);
    return (OUIDocumentProviderPreferencesViewController *)vc;
}

+ (NSString *)localizedDisplayName {
    return NSLocalizedStringFromTableInBundle(@"Use Cloud Storage Providers", @"OmniUIDocument", OMNI_BUNDLE, @"Cloud Storage Providers preference settings screen title");
}

+ (UIImage *)betaBadgeImage {
    UIImage *betaBadge = [UIImage imageNamed:@"OUIBetaBadge" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    OBASSERT_NOTNULL(betaBadge);
    
    return betaBadge;
}

+ (OFPreference *)shouldEnableDocumentProvidersPreference {
    static OFPreference *shouldEnableDocumentProvidersPreference;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shouldEnableDocumentProvidersPreference = [OFPreference preferenceForKey:@"OUIDocumentPickerShouldEnableDocumentProviders"];
    });
    
    return shouldEnableDocumentProvidersPreference;
}


- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Cloud Storage Providers", @"OmniUIDocument", OMNI_BUNDLE, @"Cloud Storage Providers preference nvigation bar title");
    
    UIImageView *betaBadgeImageView = [[UIImageView alloc] initWithImage:[[self class] betaBadgeImage]];
    UIBarButtonItem *betaBadgeBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:betaBadgeImageView];
    self.navigationItem.rightBarButtonItem = betaBadgeBarButtonItem;
    
    self.shouldEnableDocumentProviderSwitchLabel.text = [[self class] localizedDisplayName];
    self.shouldEnableDocumentProvidersSwitch.on = [[[self class] shouldEnableDocumentProvidersPreference] boolValue];
    
    [self.moreInfoButton setTitle:NSLocalizedStringFromTableInBundle(@"More Info…", @"OmniUIDocument", OMNI_BUNDLE, @"Cloud Storage Providers more information button title") forState:UIControlStateNormal];
}

- (IBAction)shouldEnableDocumentProvidersSwitchValueChanged:(id)sender {
    OUIAppController *appDelegate = (OUIAppController *)[[UIApplication sharedApplication] delegate];
    if ([appDelegate isRunningRetailDemo]) {
        [appDelegate showFeatureDisabledForRetailDemoAlertFromViewController:self];
        if ([sender isKindOfClass:[UISwitch class]]) {
            [(UISwitch *)sender setOn:NO animated:YES];
        }
    } else {
        if ([[self class] shouldEnableDocumentProvidersPreference].boolValue != self.shouldEnableDocumentProvidersSwitch.on) {
            [[[self class] shouldEnableDocumentProvidersPreference] setBoolValue:self.shouldEnableDocumentProvidersSwitch.on];
            if (!self.shouldEnableDocumentProvidersSwitch.on) {
                [[NSNotificationCenter defaultCenter] postNotificationName:OUIDocumentProviderPreferencesCloudDocumentsPreferenceTurnedOffNotification object:nil];
            }
        }
    }
}

- (IBAction)moreInfoButtonTapped:(id)sender {
    NSURL *moreInfoURL = [[OUIDocumentAppController controller] documentProviderMoreInfoURL];
    NSDictionary *emptyOptions = [NSDictionary dictionary];
    if (moreInfoURL != nil) {
        [[UIApplication sharedApplication] openURL:moreInfoURL options:emptyOptions completionHandler:nil];
    }
}

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // This is a static table view setup in a storyboard. But we can still respond to these UITableViewDataSource methods. For this one, we'd like to hide the last section if we don't have a moreInfoURL. (That way we don't have a button that doesn't do anything.) To do this, we lie about the number of sections so that the last section isn't displayed.
    NSURL *moreInfoURL = [[OUIDocumentAppController controller] documentProviderMoreInfoURL];
    if (moreInfoURL == nil) {
        return OUIDocumentProviderPreferencesSectionCount - 1;
    }
    else {
        return OUIDocumentProviderPreferencesSectionCount;
    }
}

- (nullable NSString *)tableView:(nonnull UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == OUIDocumentProviderPreferencesSectionSwitch) {
        return NSLocalizedStringFromTableInBundle(@"Turning on Cloud Storage Providers gives access to documents stored on cloud services, such as iCloud Drive or Dropbox. We are introducing access to Cloud Storage Providers as a BETA implementation; use caution when enabling this service. To learn more, see “Working in the Cloud” in the documentation.", @"OmniUIDocument", OMNI_BUNDLE, @"Cloud Storage Providers preference informational description");
    }
    
    return nil;
}

@end
