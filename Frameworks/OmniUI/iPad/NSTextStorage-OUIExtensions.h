// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
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

- (void)removeAllLinks;

/// Detects all likely app-scheme links.
- (BOOL)detectAppSchemeLinks;

@end
