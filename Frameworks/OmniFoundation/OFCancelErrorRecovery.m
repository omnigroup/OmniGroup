// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCancelErrorRecovery.h>

RCS_ID("$Id$");

@implementation OFCancelErrorRecovery

#pragma mark -
#pragma mark Subclass responsibility

+ (NSString *)defaultLocalizedRecoveryOption;
{
    return NSLocalizedStringWithDefaultValue(@"Cancel <error recovery>", @"OmniFoundation", OMNI_BUNDLE, @"Cancel", @"error recovery option");
}

- (BOOL)attemptRecoveryFromError:(NSError *)error;
{
    return NO;
}

@end
