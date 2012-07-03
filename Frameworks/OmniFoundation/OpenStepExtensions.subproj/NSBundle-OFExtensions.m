// Copyright 2005, 2007-2008, 2010, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <Security/Security.h>

RCS_ID("$Id$");


@implementation NSBundle (OFExtensions)

- (NSDictionary *)codeSigningInfoDictionary:(NSError **)error;
{
    NSURL *bundleURL = [NSURL fileURLWithPath:[self bundlePath]];
    return [[NSFileManager defaultManager] codeSigningInfoDictionaryForURL:bundleURL error:error];
}

- (NSDictionary *)codeSigningEntitlements:(NSError **)error;
{
    NSURL *bundleURL = [NSURL fileURLWithPath:[self bundlePath]];
    return [[NSFileManager defaultManager] codeSigningEntitlementsForURL:bundleURL error:error];
}

@end
