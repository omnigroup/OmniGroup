// Copyright 2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXConnection.h"

RCS_ID("$Id$")

@implementation OFXConnection

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithSessionConfiguration:(ODAV_NSURLSESSIONCONFIGURATION_CLASS *)configuration;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithSessionConfiguration:(ODAV_NSURLSESSIONCONFIGURATION_CLASS *)configuration baseURL:(NSURL *)baseURL;
{
    OBPRECONDITION(baseURL);
    
    if (!(self = [super initWithSessionConfiguration:configuration]))
        return nil;
    
    _baseURL = [baseURL copy];
    
    return self;
}

@end
