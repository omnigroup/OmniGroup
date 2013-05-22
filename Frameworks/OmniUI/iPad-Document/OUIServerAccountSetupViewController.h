// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIActionViewController.h>

@class OFXServerAccountType, OFXServerAccount;

@interface OUIServerAccountSetupViewController : OUIActionViewController

- (id)initWithAccount:(OFXServerAccount *)account ofType:(OFXServerAccountType *)accountType;

@property(nonatomic,readonly) OFXServerAccount *account;
@property(nonatomic,copy) NSString *location;
@property(nonatomic,copy) NSString *accountName;
@property(nonatomic,copy) NSString *password;
@property(nonatomic,copy) NSString *nickname;

@end
