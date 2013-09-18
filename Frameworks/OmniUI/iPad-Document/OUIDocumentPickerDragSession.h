// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

/*
 Internal helper class that helps manage a document single drag session.
 */

@class OUIDocumentPickerViewController, OUIDragGestureRecognizer;

@interface OUIDocumentPickerDragSession : NSObject

- initWithDocumentPicker:(OUIDocumentPickerViewController *)picker fileItems:(NSSet *)fileItems recognizer:(OUIDragGestureRecognizer *)dragRecognizer;

@property(nonatomic,readonly) NSSet *fileItems;

- (void)handleRecognizerChange;

@property(nonatomic,readonly) id dragDestinationItem;

@end

#import <OmniUIDocument/OUIDocumentPickerViewController.h>

@interface OUIDocumentPickerViewController (/*OUIDocumentPickerDragSession callbacks*/)
- (void)dragSessionTerminated; // For final cleanup after animation has finished
@end
