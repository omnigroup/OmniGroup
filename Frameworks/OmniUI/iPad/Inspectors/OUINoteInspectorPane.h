// Copyright 2011-2012, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUISingleViewInspectorPane.h>

@class OUINoteTextView;

@interface OUINoteInspectorPane : OUISingleViewInspectorPane <UIScrollViewDelegate, UITextViewDelegate> {
}

@property (readwrite, retain) IBOutlet OUINoteTextView *textView;
@property (nonatomic, retain) IBOutlet UIButton *enterFullScreenButton;

- (IBAction)enterFullScreen:(id)sender;


@end
