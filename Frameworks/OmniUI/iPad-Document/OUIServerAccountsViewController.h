// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UITableViewController.h>

@class OFXAgentActivity;
@class OFXServerAccount;

@interface OUIServerAccountsViewController : UITableViewController

+ (NSString *)localizedDisplayNameForBrowsing:(BOOL)isForBrowsing;

- (instancetype)initWithAgentActivity:(OFXAgentActivity *)agentActivity forBrowsing:(BOOL)isForBrowsing NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

- (void)editSettingsForAccount:(OFXServerAccount *)account;

@end
