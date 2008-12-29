// Copyright 2002-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSView.h>
#import "OAMouseTipWindow.h"

@class NSAttributedString, NSDictionary, NSString; // Foundation
@class NSTextView; // AppKit

@interface OAMouseTipView : NSView
{
    OAMouseTipStyle style;
    
    NSTextView *titleView;
    
    NSDictionary *_textAttributes;
    NSColor *backgroundColor;
    float cornerRadius;
}

// API

- (void)setStyle:(OAMouseTipStyle)aStyle;
- (void)setAttributedTitle:(NSAttributedString *)aTitle;
- (NSDictionary *)textAttributes;

- (void)setMaxSize:(NSSize)aSize;
- (NSSize)sizeOfText;

@end
