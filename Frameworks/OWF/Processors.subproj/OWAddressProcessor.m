// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
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

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Processors.subproj/OWAddressProcessor.m 68913 2005-10-03 19:36:19Z kc $");


@implementation OWAddressProcessor

// Init and dealloc

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    if (![super initWithContent:initialContent context:aPipeline])
        return nil;

    sourceAddress = [initialContent address];
    [sourceAddress retain];
    if (!sourceAddress) {
        [self release];
        return nil;
    }

    return self;
}

- (void)dealloc;
{
    [sourceAddress release];
    [super dealloc];
}

- (OWAddress *)sourceAddress;
{
    return sourceAddress;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (sourceAddress)
        [debugDictionary setObject:sourceAddress forKey:@"sourceAddress"];

    return debugDictionary;
}


@end

