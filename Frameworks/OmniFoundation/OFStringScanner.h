// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFCharacterScanner.h>

@interface OFStringScanner : OFCharacterScanner

- initWithString:(NSString *)aString;
    // Scan the specified string.  Retains string, rather than copying it, for efficiency, so don't change it.

@property(nonatomic,readonly) NSString *string;

@property(nonatomic,readonly) NSRange remainingRange;
@property(nonatomic,readonly) NSString *remainingString;

@end

