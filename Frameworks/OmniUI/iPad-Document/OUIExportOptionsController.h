// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <UIKit/UINavigationController.h>

#import <OmniUIDocument/OUIExportOptionsType.h>

@class NSFileWrapper;
@class OFXServerAccount;
@class ODSFileItem;
@class OUIDocumentExporter;

NS_ASSUME_NONNULL_BEGIN

@interface OUIExportOptionsController : NSObject

- (id)initWithServerAccount:(nullable OFXServerAccount *)serverAccount fileItem:(ODSFileItem *)fileItem exportType:(OUIExportOptionsType)exportType exporter:(OUIDocumentExporter*)exporter NS_DESIGNATED_INITIALIZER;
- (id)init NS_UNAVAILABLE;

- (void)presentInViewController:(UIViewController *)hostViewController barButtonItem:(nullable UIBarButtonItem *)barButtonItem;

@end

NS_ASSUME_NONNULL_END

