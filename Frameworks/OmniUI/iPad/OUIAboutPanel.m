// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAboutPanel.h>

#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$");

@implementation OUIAboutPanel

@synthesize iconImage;
@synthesize appNameLabel;
@synthesize appVersionLabel;
@synthesize logoImageButton;
@synthesize contactUsButton;
@synthesize infoSharingSettingsButton;
@synthesize copyrightNotice;

+ (void)displayInSheet;
{
    OUIAboutPanel *aboutPanel = [[OUIAboutPanel alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:aboutPanel];
    [aboutPanel release];
    navController.modalPresentationStyle = UIModalPresentationFormSheet;
    navController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    
    OUIAppController *appController = [OUIAppController controller];
    [appController.topViewController presentViewController:navController animated:YES completion:nil];
    
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:aboutPanel action:@selector(dismissPanel:)];
    aboutPanel.navigationItem.rightBarButtonItem = doneButton;
    [doneButton release];
    
    aboutPanel.navigationItem.title = NSLocalizedStringFromTableInBundle(@"About", @"OmniUI", OMNI_BUNDLE, @"Title of the About panel");
    
    [navController release];
}

//- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
//{
//    return [super initWithNibName:@"OUIAboutPanel" bundle:OMNI_BUNDLE];
//}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    UIImage *paneBackground = [UIImage imageNamed:@"OUIExportPane.png"];
    OBASSERT([self.view isKindOfClass:[UIImageView class]]);
    [(UIImageView *)self.view setImage:paneBackground];
    
    OUIAppController *appController = [OUIAppController controller];
    appNameLabel.text = appController.applicationName;
    
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    appVersionLabel.text = [NSString stringWithFormat:@"%@ (v%@)", [infoDictionary objectForKey:@"CFBundleShortVersionString"], [infoDictionary objectForKey:@"CFBundleVersion"]];
    
    NSString *iconImageName = [infoDictionary objectForKey:@"OUIAppIconImage"];
    iconImage.image = [UIImage imageNamed:iconImageName];
    
    NSString *logoImageName = [infoDictionary objectForKey:@"OUIAboutLogoImage"];
    [logoImageButton setImage:[UIImage imageNamed:logoImageName] forState:UIControlStateNormal];
    //[logoImageButton sizeToFit];
    
    contactUsButton.titleLabel.text = NSLocalizedStringFromTableInBundle(@"Contact Us...", @"OmniUI", OMNI_BUNDLE, @"Button title in About Panel");
    infoSharingSettingsButton.titleLabel.text = NSLocalizedStringFromTableInBundle(@"Settings for anonymous information sharing", @"OmniUI", OMNI_BUNDLE, @"Button title in About Panel");
    
    [contactUsButton.titleLabel sizeToFit];
    [infoSharingSettingsButton.titleLabel sizeToFit];
    
    NSString *copyright = [infoDictionary objectForKey:@"NSHumanReadableCopyright"];
    copyright = copyright ? copyright : @"NSHumanReadableCopyright not set!";
    copyrightNotice.text = copyright;
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

- (void)dealloc;
{
    [appNameLabel release];
    [appVersionLabel release];
    [contactUsButton release];
    [infoSharingSettingsButton release];
    [iconImage release];
    [copyrightNotice release];
    [logoImageButton release];
    [super dealloc];
}


- (IBAction)dismissPanel:(id)sender;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)emailSupport:(id)sender {
    
    [self dismissPanel:sender];
    
    // Try the first responder and then the app delegate.
    SEL action = @selector(sendFeedback:);
    UIApplication *app = [UIApplication sharedApplication];
    if ([app sendAction:action to:nil from:self forEvent:nil])
        return;
    if ([app sendAction:action to:app.delegate from:self forEvent:nil])
        return;
    
    NSLog(@"No target found for menu action %@", NSStringFromSelector(action));
}

- (IBAction)viewInAppStore:(id)sender {
    NSString *appStoreURLString = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIAppStoreURL"];
    if (appStoreURLString.length) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:appStoreURLString]];
    }
}

- (IBAction)tappedLogoImage:(id)sender {
    NSString *appStoreURLString = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUICompanyAppStoreURL"];
    if (appStoreURLString.length) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:appStoreURLString]];
    }
}

- (IBAction)viewDataSharingPrefs:(id)sender {
    NSLog(@"View data sharing prefs");
}

@end
