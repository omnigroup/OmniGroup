// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/NSTextStorage.h>

@class OUITextView;

@interface NSTextStorage (OUIExtensions)

- (NSArray *)textSpansInRange:(NSRange)range inTextView:(OUITextView *)textView; // Array of OUITextSelectionSpans
- (NSTextStorage *)underlyingTextStorage; // Defaults to self. Used as the target for inspector changes.

@end
