// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWAddressProcessor.h>
#import <OWF/OWContent.h>
#import <OWF/OWAddress.h>

#import <Foundation/NSString.h>
#import <Foundation/NSDictionary.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");


@implementation OWAddressProcessor

// Init and dealloc

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    if (!(self = [super initWithContent:initialContent context:aPipeline]))
        return nil;

    sourceAddress = [initialContent address];
    if (sourceAddress == nil) {
        self = nil;
        return nil;
    }

    return self;
}

- (OWAddress *)sourceAddress;
{
    return sourceAddress;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    if (sourceAddress)
        [debugDictionary setObject:sourceAddress forKey:@"sourceAddress"];

    return debugDictionary;
}


@end

