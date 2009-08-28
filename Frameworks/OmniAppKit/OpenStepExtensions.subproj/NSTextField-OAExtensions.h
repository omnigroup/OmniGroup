// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSTextField.h>
#import <OmniAppKit/NSControl-OAExtensions.h>

@interface NSTextField (OAExtensions)
- (void)setStringValueAllowingNil: (NSString *) aString;
- (void)appendString:(NSString *)aString;

- (void)changeColorAsIfEnabledStateWas:(BOOL)newEnabled;

@end
