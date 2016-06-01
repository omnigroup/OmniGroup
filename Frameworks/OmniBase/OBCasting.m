// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@implementation NSObject (OBAsSelf)

+ (instancetype)asSelf:(id)object;
{
    if ([object isKindOfClass:self])
        return object;
    return nil;
}

@end

