// Copyright 2004-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OWF/OWF.h>

RCS_ID("$Id$");

@interface OWFGetURLFetcher : OFObject <OWTarget>

+ (void)getURLString:(NSString *)urlString;
- (id)initWithAddress:(OWAddress *)anAddress;
- (void)printData;

@end

@interface OWPipeline (Private)
+ (void)setDebug:(BOOL)debug;
@end

int main(int argc, char *argv[])
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s url\n", argv[0]);
        exit(1);
    }
    OMNI_POOL_START {
        [OBPostLoader processClasses];
        [[OFController sharedController] didInitialize];
        [[OFController sharedController] startedRunning];
        [[OFScheduler dedicatedThreadScheduler] setInvokesEventsInMainThread:NO];
        [OWPipeline setDebug:YES];
    } OMNI_POOL_END;
    OMNI_POOL_START {
        [OWFGetURLFetcher getURLString:[NSString stringWithCString:argv[1]]];
    } OMNI_POOL_END;
    return 0;
}

@implementation OWFGetURLFetcher
{
    NSConditionLock *dataStreamReadyLock;
    OWContent *content;
}

enum { NOT_READY, READY };

+ (void)getURLString:(NSString *)urlString;
{
    OWAddress *address = [OWAddress addressForDirtyString:urlString];
    NSLog(@"address = %@", [address addressString]);

    OWFGetURLFetcher *fetcher;

    OMNI_POOL_START {
        fetcher = [[self alloc] initWithAddress:address];
    } OMNI_POOL_END;
    OMNI_POOL_START {
        [fetcher printData];
    } OMNI_POOL_END;
    OMNI_POOL_START {
        [fetcher release];
    } OMNI_POOL_END;
}

- (id)initWithAddress:(OWAddress *)anAddress;
{
    if (!(self = [super init]))
        return nil;

    dataStreamReadyLock = [[NSConditionLock alloc] initWithCondition:NOT_READY];
    [OWWebPipeline startPipelineWithAddress:anAddress target:self];

    return self;
}

- (void)printData;
{
    [dataStreamReadyLock lockWhenCondition:READY];
    [dataStreamReadyLock unlock];

    OWDataStreamCursor *cursor = [content dataCursor];
    NSData *data;

    while ((data = [cursor readData]) != nil && [data length] != 0) {
        size_t bytesWritten = fwrite([data bytes], [data length], 1, stdout);
        OBASSERT(bytesWritten == 1);
    }
}

//
// OWTarget
//

- (OWContentType *)targetContentType;
{
    return [OWContentType sourceContentType];
}

- (OWTargetContentDisposition)pipeline:(OWPipeline *)aPipeline hasContent:(OWContent *)someContent flags:(OWTargetContentOffer)contentFlags;
{
    switch (contentFlags) {
        case OWContentOfferDesired:
            content = [someContent retain];
            break;
        case OWContentOfferAlternate:
        case OWContentOfferError:
        case OWContentOfferFailure:
            break;
    } 

    [dataStreamReadyLock lock];
    [dataStreamReadyLock unlockWithCondition:READY];

    return OWTargetContentDisposition_ContentAccepted;
}

- (OWContentInfo *)parentContentInfo;
{
    return [OWContentInfo headerContentInfoWithName:@"Fetch"];
}

- (NSString *)targetTypeFormatString;
{
    return @"Fetch";
}

//
// OWOptionalTarget informal protocol
//

- (void)pipelineDidEnd:(OWPipeline *)aPipeline;
{
    [OWPipeline invalidatePipelinesForTarget:self];
}

@end
