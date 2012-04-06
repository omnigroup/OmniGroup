// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIViewController.h>

@class OUIDocumentStoreSetupViewController;

@interface OUIDocumentStoreSetupViewController : OUIViewController <UITableViewDelegate, UITableViewDataSource>

- initWithOriginalState:(BOOL)originalUseICloud dismissAction:(void (^)(BOOL cancelled))dismissAction;

@property(nonatomic) BOOL useICloud;
@property(nonatomic) BOOL shouldMigrateExistingDocuments; // Move when going into iCloud, copy when migrating out.

- (void)cancel;

@end
