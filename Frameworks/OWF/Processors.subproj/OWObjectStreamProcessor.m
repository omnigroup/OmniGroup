// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWObjectStreamProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContent.h>
#import <OWF/OWObjectStreamCursor.h>
#import <OWF/OWPipeline.h>

RCS_ID("$Id$")

@implementation OWObjectStreamProcessor

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    if (!(self = [super initWithContent:initialContent context:aPipeline]))
	return nil;

    objectCursor = [initialContent objectCursor];

    return self;
}

// OWProcessor subclass

- (void)abortProcessing;
{
    [objectCursor abort];
    [super abortProcessing];
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    if (objectCursor)
        [debugDictionary setObject:objectCursor forKey:@"objectCursor"];

    return debugDictionary;
}

@end
