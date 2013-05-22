// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXAccountClientParameters.h>

RCS_ID("$Id$")

static NSTimeInterval OFXAccountInfoClientWriteInterval;
static NSTimeInterval OFXAccountInfoClientStaleInterval;

@implementation OFXAccountClientParameters

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBInitializeTimeInterval(OFXAccountInfoClientWriteInterval, 60*60, 10, 60*60); // Update our client record about every hour.
    OBInitializeTimeInterval(OFXAccountInfoClientStaleInterval, 14*24*60*60, 15, 14*24*60*60); // Remove old clients that haven't been updated in a couple weeks or so.
}

- initWithDefaultClientIdentifierPreferenceKey:(NSString *)defaultClientIdentifierPreferenceKey hostIdentifierDomain:(NSString *)hostIdentifierDomain currentFrameworkVersion:(OFVersionNumber *)currentFrameworkVersion;
{
    if (!(self = [super initWithDefaultClientIdentifierPreferenceKey:defaultClientIdentifierPreferenceKey hostIdentifierDomain:hostIdentifierDomain currentFrameworkVersion:currentFrameworkVersion]))
        return nil;
    
    _writeInterval = OFXAccountInfoClientWriteInterval;
    _staleInterval = OFXAccountInfoClientStaleInterval;
    
    return self;
}

@end
