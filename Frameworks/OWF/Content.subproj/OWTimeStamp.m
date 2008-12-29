// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWTimeStamp.h>

#import <objc/objc-class.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

// #import <OWF/OWContentCache.h>
#import <OWF/OWContentType.h>

RCS_ID("$Id$")


@implementation OWTimeStamp

static OWContentType *lastChangedContentType = nil;

+ (void)initialize
{
    static BOOL                 initialized = NO;

    [super initialize];
    if (initialized)
        return;
    initialized = YES;

    lastChangedContentType = [OWContentType contentTypeForString:@"TimeStamp/LastChanged"];
}

+ (OWContentType *)lastChangedContentType;
{
    return lastChangedContentType;
}

#if 0
+ (NSDate *)dateForAddress:(OWAddress *)address;
{
    OWContentCache	*contentCache;

    contentCache = [OWContentCache lookupContentCacheForAddress:address];
    if (!contentCache)
        return nil;

    return [self dateForContentCache:contentCache];
}
#endif

// Init and dealloc

- initWithDate:(NSDate *)aDate contentType:(OWContentType *)aType;
{
    [super init];
    date = [aDate retain];
    type = aType;
    return self;
}

- (void)dealloc;
{
    [date release];
    [super dealloc];
}


// Public API

- (NSDate *)date;
{
    return date;
}


// OWContent protocol

- (OWContentType *)contentType;
{
    return type;
}

- (BOOL)shareable;
{
    return YES;
}

@end

