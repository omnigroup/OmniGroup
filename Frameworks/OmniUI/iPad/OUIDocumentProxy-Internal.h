// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@protocol OUIDocumentPreview;

@interface OUIDocumentProxy (/*Internal*/)
- (void)startPreviewLoad;
- (void)startPreviewLoadIfNeeded;
- (void)cancelPreviewLoadIfRunning;
- (void)discardPreview;
- (id <OUIDocumentPreview>)currentPreview;
- (void)previewDidLoad:(id <OUIDocumentPreview>)preview;
@end

