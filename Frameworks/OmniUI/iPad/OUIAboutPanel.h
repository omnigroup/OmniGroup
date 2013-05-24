// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@interface OUIAboutPanel : UIViewController {
    UILabel *appNameLabel;
    UILabel *appVersionLabel;
    UIButton *logoImageButton;
    UIButton *contactUsButton;
    UIButton *infoSharingSettingsButton;
    UILabel *copyrightNotice;
    UIImageView *iconImage;
}

+ (void)displayInSheet;

@property (nonatomic, retain) IBOutlet UIImageView *iconImage;
@property (nonatomic, retain) IBOutlet UILabel *appNameLabel;
@property (nonatomic, retain) IBOutlet UILabel *appVersionLabel;
@property (nonatomic, retain) IBOutlet UIButton *logoImageButton;
@property (nonatomic, retain) IBOutlet UIButton *contactUsButton;
@property (nonatomic, retain) IBOutlet UIButton *infoSharingSettingsButton;
@property (nonatomic, retain) IBOutlet UILabel *copyrightNotice;

- (IBAction)dismissPanel:(id)sender;
- (IBAction)emailSupport:(id)sender;
- (IBAction)viewInAppStore:(id)sender;
- (IBAction)tappedLogoImage:(id)sender;
- (IBAction)viewDataSharingPrefs:(id)sender;

@end
