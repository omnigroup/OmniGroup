// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@interface OUIDocumentPickerSettings : NSObject

@property(nonatomic,copy) NSArray *availableScopes;
@property(nonatomic,copy) NSArray *availableImportExportAccounts;

- (void)showFromView:(UIView *)view inViewController:(UIViewController *)currentController;

@end

#import <OmniFileStore/OFSDocumentStoreScope.h>

@interface OFSDocumentStoreScope (OUIDocumentPickerSettings)
@property(nonatomic,readonly) NSString *settingsImageName;
@end
