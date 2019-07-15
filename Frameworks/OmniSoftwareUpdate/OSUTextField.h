// Copyright 2009-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSTextField.h>

@interface OSUTextField : NSTextField
{
}

// API
- (BOOL)textView:(NSTextView *)aTextView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex;


@end
