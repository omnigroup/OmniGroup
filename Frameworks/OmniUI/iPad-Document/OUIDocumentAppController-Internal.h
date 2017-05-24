// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUIDocument/OUIDocumentAppController.h>

@class OFXServerAccount;
@class UIDocumentPickerViewController;

@interface OUIDocumentAppController ()
// The following three properties can be overridden to point your documents at a non-standard location. For example, you may want to have your app's documents stored in a container shared by other apps.
@property (readonly) NSURL *_localDirectoryURL;
@property (readonly) NSURL *_trashDirectoryURL;
@property (readonly) NSURL *_templatesDirectoryURL;

- (void)_didAddSyncAccount:(OFXServerAccount *)account;
- (void)_selectScopeWithAccount:(OFXServerAccount *)account completionHandler:(void (^)(void))completionHandler;
- (void)_presentExternalDocumentPicker:(UIDocumentPickerViewController *)externalDocumentPicker completionBlock:(void (^)(NSURL *))externalPickerCompletionBlock;
@end
