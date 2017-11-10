// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFStringScanner.h>

RCS_ID("$Id$")

@implementation OFStringScanner
{
    NSString *_string;
}

- (id)initWithString:(NSString *)aString;
{
    if (!(self = [super init]))
        return nil;

    _string = [aString retain];
    [self fetchMoreDataFromString:aString];

    return self;
}

- (void)dealloc;
{
    [_string release];
    [super dealloc];
}

- (NSRange)remainingRange;
{
    NSUInteger location = self.scanLocation;
    NSUInteger length = [_string length];
    OBASSERT(location <= length);
    return NSMakeRange(location, length - location);
}

- (NSString *)remainingString;
{
    return [_string substringWithRange:self.remainingRange];
}

@end
