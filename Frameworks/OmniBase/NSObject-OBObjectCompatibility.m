// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/NSObject-OBObjectCompatibility.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@implementation NSObject (OBObjectCompatibility)

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [NSMutableDictionary dictionary];
    [debugDictionary setObject:[self shortDescription] forKey:@"__self__"];
    return debugDictionary;
}

- (NSString *)shortDescription;
{
    return [self description];
}

@end
