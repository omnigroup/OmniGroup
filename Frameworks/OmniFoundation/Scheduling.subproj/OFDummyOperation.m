// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDummyOperation.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

@implementation OFDummyOperation
{
    NSError *_error;
    NSObject *_result;
}

@synthesize error = _error;
@synthesize result = _result;

- (instancetype)initWithResult:(NSObject *)obj;
{
    if (!(self = [super init])) {
        return nil;
    }
    _result = obj;
    return self;
}

- (instancetype)initWithError:(NSError *)obj;
{
    if (!(self = [super init])) {
        return nil;
    }
    _error = obj;
    return self;
}

- (void)main
{
    /* nothing to do */
}

@end
