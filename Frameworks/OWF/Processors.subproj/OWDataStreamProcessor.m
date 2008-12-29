// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWDataStreamProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContent.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWDataStreamCursor.h>
#import <OWF/OWPipeline.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Processors.subproj/OWDataStreamProcessor.m 68913 2005-10-03 19:36:19Z kc $")

@implementation OWDataStreamProcessor

// Init and dealloc

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    if (![super initWithContent:initialContent context:aPipeline])
        return nil;

    dataCursor = [[initialContent dataCursor] retain];
    if (!dataCursor) {
        [self release];
        return nil;
    }

    return self;
}

- (void)dealloc;
{
    [dataCursor release];
    [super dealloc];
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (dataCursor)
        [debugDictionary setObject:dataCursor forKey:@"dataCursor"];

    return debugDictionary;
}

@end
