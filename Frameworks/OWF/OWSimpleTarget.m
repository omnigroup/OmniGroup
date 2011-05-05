// Copyright 2000-2005, 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWSimpleTarget.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OWAddress.h"
#import "OWContentInfo.h"
#import "OWContentType.h"
#import "OWDataStream.h"
#import "OWDataStreamCursor.h"
#import "OWHeaderDictionary.h"
#import "OWPipeline.h"
#import "OWProcessor.h"

RCS_ID("$Id$")

@interface OWSimpleTarget (Private)
- (void)_setResultingContent:(OWContent *)someContent;
@end

@implementation OWSimpleTarget

enum { OWSimpleTargetNoResult, OWSimpleTargetHaveResult };

// Init and dealloc

- (id)initWithParentContentInfo:(OWContentInfo *)contentInfo targetContentType:(OWContentType *)contentType initialContent:(OWContent *)someContent;
{
    if (!(self = [super init]))
        return nil;

    OFWeakRetainConcreteImplementation_INIT;

    initialContent = [someContent retain];
    parentContentInfo = [contentInfo retain];
    targetContentType = [contentType retain];
    resultLock = [[NSConditionLock alloc] initWithCondition:OWSimpleTargetNoResult];
    targetTypeFormatString = nil;

    return self;
}

- (void)dealloc;
{
    OFWeakRetainConcreteImplementation_DEALLOC;

    [initialContent release];
    [parentContentInfo release];
    [targetContentType release];
    [targetTypeFormatString release];
    [resultLock release];
    [resultingContent release];
    [addressOfLastContent release];
    
    [super dealloc];
}

// API

- (void)setTargetTypeFormatString:(NSString *)newFormatString;
{
    if (newFormatString == targetTypeFormatString)
        return;
        
    [targetTypeFormatString release];
    targetTypeFormatString = [newFormatString retain];
}

- (void)startProcessingContent;
{
    OWPipeline *pipeline = [[OWPipeline alloc] initWithContent:initialContent target:self];
    [pipeline startProcessingContent];
    [pipeline release];
}

- (OWContent *)resultingContent;
{
    [resultLock lockWhenCondition:OWSimpleTargetHaveResult];
    OWContent *someContent = [resultingContent retain];
    [resultLock unlock];
    
    return [someContent autorelease];
}

- (OWTargetContentOffer)resultingContentFlags;
{
    [resultLock lockWhenCondition:OWSimpleTargetHaveResult];
    OWTargetContentOffer flags = resultingContentFlags;
    [resultLock unlock];
    
    return flags;
}

- (OWAddress *)lastAddress;
{
    return addressOfLastContent;
}

// OFWeakRetain protocol

OFWeakRetainConcreteImplementation_IMPLEMENTATION

- (void)invalidateWeakRetains;
{
    [OWPipeline invalidatePipelinesForTarget:self];
}

// OWTarget protocol

- (OWContentType *)targetContentType;
{
    return targetContentType;
}

- (OWTargetContentDisposition)pipeline:(OWPipeline *)aPipeline hasContent:(OWContent *)someContent flags:(OWTargetContentOffer)flags;
{
    [resultLock lock];
    
    addressOfLastContent = [[aPipeline lastAddress] retain];
    
    NSLog(@"-[%@ %@], someContent=%@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), someContent);
    
    if (resultingContent != someContent) {
        [resultingContent release];
        resultingContent = [someContent retain];
    }
    
    resultingContentFlags = flags;
    
    [resultLock unlockWithCondition:OWSimpleTargetHaveResult];
    
    return OWTargetContentDisposition_ContentAccepted;
}

- (BOOL)acceptsAlternateContent
{
    /* In general, users of this class specify exactly the type they want, even if acceptsAlternateContent is YES. This is a hint to the pipeline that we probably won't do anything useful if it hands us something completely unexpected (but we might try). */
    return NO;
}

- (void)pipelineDidEnd:(OWPipeline *)aPipeline;
{
    [self _setResultingContent:resultingContent];
}

- (NSString *)targetTypeFormatString;
{
    if (targetTypeFormatString != nil)
        return targetTypeFormatString;
    else
        return NSLocalizedStringFromTableInBundle(@"%@ File", @"OWF", [OWSimpleTarget bundle], "simpleTarget targetTypeFormatString - generic description when no type string is supplied");
}

- (OWContentInfo *)parentContentInfo;
{
    return parentContentInfo;
}

@end

@implementation OWSimpleTarget (Private)

- (void)_setResultingContent:(OWContent *)someContent;
{
}

@end
