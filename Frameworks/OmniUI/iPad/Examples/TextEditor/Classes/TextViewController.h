// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniUI/OUITextView.h>
#import <OmniUIDocument/OUIDocumentViewController.h>

@class OUITextView;

@interface TextViewController : UIViewController <OUIDocumentViewController, OUITextViewDelegate>

@property(nonatomic,readonly) OUITextView *textView; // alias for our -view.

@property(nonatomic) CGFloat scale;

@property(nonatomic) BOOL forPreviewGeneration;

- (void)documentDidClose;

@end
