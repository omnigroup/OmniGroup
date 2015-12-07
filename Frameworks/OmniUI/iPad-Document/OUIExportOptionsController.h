// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

#import <OmniUIDocument/OUIExportOptionsType.h>

@class NSFileWrapper;
@class OFXServerAccount;
@class ODSFileItem;
@class OUIDocumentExporter;

@interface OUIExportOptionsController : UIViewController <UIDocumentInteractionControllerDelegate>

- (id)initWithServerAccount:(OFXServerAccount *)serverAccount fileItem:(ODSFileItem *)fileItem exportType:(OUIExportOptionsType)exportType exporter:(OUIDocumentExporter*)exporter NS_DESIGNATED_INITIALIZER;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (id)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end
