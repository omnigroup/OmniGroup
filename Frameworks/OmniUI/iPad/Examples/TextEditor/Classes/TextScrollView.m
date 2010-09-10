// Copyright 2010 The Omni Group.  All rights reserved.
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

- (void)layoutSubviews;
{
    OBPRECONDITION(_textView); // not hooked up in xib?
    
    if (_textView) {
        CGRect bounds = self.bounds;
        
        // First make sure the text is the right width so that it can calculate the right used height
        CGRect textFrame = _textView.frame;
        if (textFrame.size.width != bounds.size.width) {
            _textView.frame = CGRectMake(0, 0, bounds.size.width, textFrame.size.height);
        }
        
        // Then ensure the height is large enough to span the text (or our height).
        CGSize usedSize = _textView.viewUsedSize;
        CGFloat height = MAX(bounds.size.height, usedSize.height);
        if (height != textFrame.size.height) {
            _textView.frame = CGRectMake(0, 0, bounds.size.width, height);
        }
    }
    
    [super layoutSubviews];
}

@end
