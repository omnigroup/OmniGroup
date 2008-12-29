// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCancelErrorRecovery.h>

#import <OmniFoundation/NSBundle-OFExtensions.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/OmniGroup/Frameworks/OmniFoundation/OFErrorRecovery.m 89919 2007-08-10 21:12:37Z bungi $");

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
