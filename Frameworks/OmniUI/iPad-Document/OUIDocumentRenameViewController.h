// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIViewController.h>

@class OUIDocumentPicker, OFSDocumentStoreFileItem;

// Helper view controller for rename operations in OUIDocumentPicker
@interface OUIDocumentRenameViewController : OUIViewController

- initWithDocumentPicker:(OUIDocumentPicker *)picker fileItem:(OFSDocumentStoreFileItem *)fileItem;

- (void)startRenaming;
- (void)cancelRenaming;

@end


// Internal callbacks that we expect OUIDocumentPicker to have
#import <OmniUIDocument/OUIDocumentPicker.h>
@interface OUIDocumentPicker (/*OUIDocumentRenameViewController*/)
- (void)_didPerformRenameToFileURL:(NSURL *)destinationURL;
- (void)_didStopRenamingFileItem;
@end
