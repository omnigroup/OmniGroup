// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSView.h>

@class NSFont, NSString;

@interface OAShrinkingTextDisplayer : NSView
{
    NSFont *baseFont;
    NSString *string;
}

- (void)setFont:(NSFont *)font;
- (NSFont *)font;

- (void)setStringValue:(NSString *)newString;
- (NSString *)stringValue;

@end
