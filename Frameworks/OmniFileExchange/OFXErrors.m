// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXErrors.h>

RCS_ID("$Id$")

NSString * const OFXErrorDomain = @"com.omnigroup.frameworks.OmniFileExchange.ErrorDomain";

@implementation OFXRecentError

+ (instancetype)recentError:(NSError *)error withDate:(NSDate *)date;
{
    return [[self alloc] initWithError:error withDate:date];
}

- (instancetype)initWithError:(NSError *)error withDate:(NSDate *)date;
{
    if (!(self = [super init]))
        return nil;
    
    _error = error;
    _date = date;
    
    return self;
}

@end
