// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSString;

#import <OmniAppKit/OAFindControllerTargetProtocol.h>

@interface OAFindPattern : NSObject <OAFindPattern>
{
    NSString *pattern;
    unsigned int optionsMask;
    BOOL wholeWord;
    NSString *replacementString;
}

- initWithString:(NSString *)aString ignoreCase:(BOOL)ignoreCase wholeWord:(BOOL)isWholeWord backwards:(BOOL)backwards;

@end
