// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFRegularExpression, OFRegularExpressionMatch;

#import <OmniAppKit/OAFindControllerTargetProtocol.h>

#define SELECT_FULL_EXPRESSION (-1)

@interface OARegExFindPattern : NSObject <OAFindPattern>
{
    OFRegularExpression *regularExpression;
    OFRegularExpressionMatch *lastMatch;
    BOOL isBackwards;
    int selectedSubexpression;
    
    NSString *replacementString;
}

- initWithString:(NSString *)aString selectedSubexpression:(int)subexpression backwards:(BOOL)backwards;

@end
