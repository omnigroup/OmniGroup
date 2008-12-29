// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@interface OFMultipleOptionErrorRecovery : NSObject
{
    NSArray *_recoveries;
}

// The list of options can be a mixture of strings and class objects (subclasses of OFErrorRecovery).  If a string is found, it is used as the title for the next OFErrorRecover created.  Otherwise, the OFErrorRecovery's default title is used.  If two strings in a row are found or a string is found before the terminating nil, the behavior is undefined, but currently you'll get an assertion failure and the string will be ignored.
+ (NSError *)errorRecoveryErrorWithError:(NSError *)error object:(id)object options:(id)option1, ... NS_REQUIRES_NIL_TERMINATION;

- initWithRecoveries:(NSArray *)recoveries;
- (NSArray *)recoveries;

// Informal protocol shared beteween OFErrorRecovery and OFMultipleOptionErrorRecovery
- (id)firstRecoveryOfClass:(Class)cls;

@end
