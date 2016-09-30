// Copyright 2000-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWSimpleTarget.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWAddress.h>
#import <OWF/OWContentInfo.h>
#import <OWF/OWContentType.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWDataStreamCursor.h>
#import <OWF/OWHeaderDictionary.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWProcessor.h>

RCS_ID("$Id$")

@implementation OWSimpleTarget
{
    OWContent *initialContent;
    
    OWContentInfo *parentContentInfo;
    OWContentType *targetContentType;
    NSString *targetTypeFormatString;
    
    NSConditionLock *resultLock;
    OWContent *resultingContent;
    OWTargetContentOffer resultingContentFlags;
    OWAddress *addressOfLastContent;
}

enum { OWSimpleTargetNoResult, OWSimpleTargetHaveResult };

// Init and dealloc

- (id)initWithParentContentInfo:(OWContentInfo *)contentInfo targetContentType:(OWContentType *)contentType initialContent:(OWContent *)someContent;
{
    if (!(self = [super init]))
        return nil;

    initialContent = someContent;
    parentContentInfo = contentInfo;
    targetContentType = contentType;
    resultLock = [[NSConditionLock alloc] initWithCondition:OWSimpleTargetNoResult];
    targetTypeFormatString = nil;

    return self;
}

- (void)dealloc;
{
    [OWPipeline invalidatePipelinesForTarget:self];
}

// API

- (void)setTargetTypeFormatString:(NSString *)newFormatString;
{
    if (newFormatString == targetTypeFormatString)
        return;
        
    targetTypeFormatString = newFormatString;
}

- (void)startProcessingContent;
{
    OWPipeline *pipeline = [[OWPipeline alloc] initWithContent:initialContent target:self];
    [pipeline startProcessingContent];
}

- (OWContent *)resultingContent;
{
    [resultLock lockWhenCondition:OWSimpleTargetHaveResult];
    OWContent *someContent = resultingContent;
    [resultLock unlock];
    
    return someContent;
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

// OWTarget protocol

- (OWContentType *)targetContentType;
{
    return targetContentType;
}

- (OWTargetContentDisposition)pipeline:(OWPipeline *)aPipeline hasContent:(OWContent *)someContent flags:(OWTargetContentOffer)flags;
{
    [resultLock lock];
    
    addressOfLastContent = [aPipeline lastAddress];
    
    NSLog(@"-[%@ %@], someContent=%@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), someContent);
    
    if (resultingContent != someContent) {
        resultingContent = someContent;
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
