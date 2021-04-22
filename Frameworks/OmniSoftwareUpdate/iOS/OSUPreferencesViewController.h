// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UITableViewController.h>

@class OUIMenuOption;
@class OSUProbe;

@interface OSUPreferencesViewController : UITableViewController

// Strings for displaying before navigating to this view controller
+ (NSString *)localizedSectionTitle;
+ (NSString *)localizedDisplayName;
+ (NSString *)localizedDetailDescription;
+ (NSString *)localizedLongDescription;
+ (BOOL)sendAnonymousDeviceInformationEnabled;

+ (OUIMenuOption *)menuOption NS_EXTENSION_UNAVAILABLE_IOS("");

// Subclass API

/// Return a custom UIViewController to be used when displaying an OSUProbe with the "app-specific display" option. Apps that create probes with this option must subclass this class and override this method to return a view controller; otherwise, the probe's raw value will be displayed.
- (__kindof UIViewController *)appSpecificDisplayControllerForProbe:(OSUProbe *)probe;

@end

#pragma mark -

@interface OSUPreferencesTableViewLabel : UIView

@property (nonatomic, copy) UIColor *textColor;

@end
