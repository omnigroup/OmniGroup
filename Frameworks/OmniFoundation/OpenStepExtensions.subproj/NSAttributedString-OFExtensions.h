// Copyright 1997-2005,2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSAttributedString.h>

@class NSArray, NSSet, NSString;

@interface NSAttributedString (OFExtensions)

- initWithString:(NSString *)str attributeName:(NSString *)attributeName attributeValue:(id)attributeValue;
    // This can be used to initialize an attributed string when you only want to set one attribute:  this way, you don't have to build an NSDictionary of attributes yourself.

- (NSArray *)componentsSeparatedByString:(NSString *)aString;

- (NSSet *)valuesOfAttribute:(NSString *)attributeName inRange:(NSRange)aRange;

@end
