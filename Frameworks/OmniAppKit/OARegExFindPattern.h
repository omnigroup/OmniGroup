// Copyright 2001-2005, 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniAppKit/OAFindPattern.h>

#define SELECT_FULL_EXPRESSION (-1)

@interface OARegExFindPattern : NSObject <OAFindPattern>

- initWithPattern:(NSString *)pattern selectedCaptureGroup:(NSInteger)captureGroup backwards:(BOOL)backwards;

@end
