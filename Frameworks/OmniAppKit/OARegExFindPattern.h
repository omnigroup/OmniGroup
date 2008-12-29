// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OARegExFindPattern.h 68913 2005-10-03 19:36:19Z kc $

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
