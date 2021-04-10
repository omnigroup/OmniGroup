// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UITableViewController.h>
#import <OmniUIDocument/OUIDocumentExporter.h>

@class ODAVFileInfo;

@interface OUIFileListViewController : UITableViewController

@property (nonatomic, copy) NSArray *files;

/*!
 * \brief Defaults to YES.
 */
@property (nonatomic, assign) BOOL shouldShowLastModifiedDate;

- (NSString *)localizedNameForFileName:(NSString *)fileName;

// Private
- (BOOL)_canOpenFile:(ODAVFileInfo *)fileInfo;

@end
