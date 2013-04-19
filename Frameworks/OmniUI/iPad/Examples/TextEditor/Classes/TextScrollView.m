// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "TextScrollView.h"

#import <OmniUI/OUIEditableFrame.h>

RCS_ID("$Id$");

@implementation TextScrollView

@synthesize textView = _textView;

- (void)dealloc;
{
    [_textView release];
    [super dealloc];
}

- (void)layoutSubviews;
{
    OBPRECONDITION(_textView); // not hooked up in xib?
    
    if (_textView) {
        CGRect bounds = self.bounds;
        
        // First make sure the text is the right width so that it can calculate the right used height
        CGRect textFrame = _textView.frame;
        if (textFrame.size.width != bounds.size.width) {
            textFrame.size.width = bounds.size.width;
        }
        
        // Then ensure the height is large enough to span the text (or our height).
        CGSize usedSize = _textView.viewUsedSize;
        CGFloat height = MAX(bounds.size.height, usedSize.height);
        if (height != textFrame.size.height) {
           textFrame.size.height = height;
        }
        
        // Adjust the textView frame only if needed
        if (!CGRectEqualToRect(_textView.frame, textFrame)) {
            _textView.frame = textFrame;
        }

        // Adjust the contentSize so we can scroll
        if (!CGSizeEqualToSize(self.contentSize, textFrame.size)) {
            self.contentSize = textFrame.size;
        }
    }
    
    [super layoutSubviews];
}

@end
