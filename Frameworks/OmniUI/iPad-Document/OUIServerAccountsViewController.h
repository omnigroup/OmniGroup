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

@property(class,readonly,nonatomic) NSString *localizedDisplayName;
@property(class,readonly,nonatomic) NSString *localizedDisplayDetailText;

- (instancetype)initWithAgentActivity:(OFXAgentActivity *)agentActivity NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;

- (void)editSettingsForAccount:(OFXServerAccount *)account;

@end
