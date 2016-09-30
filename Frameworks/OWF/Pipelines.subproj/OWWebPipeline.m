// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWWebPipeline.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/NSDate-OWExtensions.h>
#import <OWF/OWAddress.h>
#import <OWF/OWContent.h>
#import <OWF/OWContentCacheProtocols.h>
#import <OWF/OWContentInfo.h>
#import <OWF/OWCookieDomain.h>
#import <OWF/OWCookie.h>
#import <OWF/OWHeaderDictionary.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

#warning correctly make use of OWWebPipelineReferringContentInfoKey when applied to an OWAddress by OmniWebKit
NSString * const OWWebPipelineReferringContentInfoKey = @"OWWebPipelineReferringContentInfoKey";

@implementation OWWebPipeline

static OFScheduler *refreshScheduler;
OFCharacterSet *WhitespaceSet;
OFCharacterSet *CacheControlNameDelimiterSet;
OFCharacterSet *CacheControlValueDelimiterSet;

+ (void)initialize;
{
    OBINITIALIZE;

    refreshScheduler = [[OFScheduler mainScheduler] subscheduler];

    WhitespaceSet = [[OFCharacterSet alloc] initWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    CacheControlNameDelimiterSet = [[OFCharacterSet alloc] initWithOFCharacterSet:WhitespaceSet];
    [CacheControlNameDelimiterSet addCharacter:','];
    [CacheControlNameDelimiterSet addCharacter:'='];

    CacheControlValueDelimiterSet = [[OFCharacterSet alloc] initWithOFCharacterSet:WhitespaceSet];
    [CacheControlValueDelimiterSet addCharacter:','];
}

- initWithContent:(OWContent *)aContent target:(id <OWTarget, NSObject>)aTarget;
{
    if (!(self = [super initWithContent:aContent target:aTarget]))
        return nil;

    historyAction = OWWebPipelineForwardHistoryAction;

#if 0
    // TODO - This is a fallback for when the referrer isn't specified explicitly. Should it be here at all?
    if ([self contextObjectForKey:OWCacheArcReferringContentKey] == nil)
        [self setReferringContentInfo:parentContentInfo];
#endif
    
    return self;
}

#if 0  // Obsolete. Use the OWCacheArcReferringAddressKey and OWCacheArcReferringContentKey context info keys.
- (OWAddress *)referringAddress;
{
    return referringAddress;
}

- (OWContentInfo *)referringContentInfo
{
    return referringContentInfo;
}
#endif

- (OWWebPipelineHistoryAction)historyAction;
{
    return historyAction;
}

- (void)setHistoryAction:(OWWebPipelineHistoryAction)newHistoryAction;
{
    historyAction = newHistoryAction;
}

- (BOOL)proxyCacheDisabled;
{
    NSString *cacheControl = [self contextObjectForKey:OWCacheArcCacheBehaviorKey];
    if (cacheControl &&
        ([cacheControl isEqualToString:OWCacheArcReload] || [cacheControl isEqualToString:OWCacheArcRevalidate]))
        return YES;
        
    return NO /* || (lastAddress && [lastAddress isAlwaysUnique]) */;
}

- (void)setProxyCacheDisabled:(BOOL)newDisabled;
{
    if (![self proxyCacheDisabled])
        [self setContextObject:OWCacheArcReload forKey:OWCacheArcCacheBehaviorKey];
}

@end

@implementation OWWebPipeline (Private)

#if 0
// KHTML/WebCore handles Refresh: headers now.

- (void)_setRefreshEvent:(OFScheduledEvent *) aRefreshEvent;
{
    OBPRECONDITION(!refreshEvent);
    refreshEvent = [aRefreshEvent retain];
}

- (void)_processRefreshHeader:(NSString *)refresh;
{
    NSString *refreshTimeString, *urlString;
    NSTimeInterval refreshTimeInterval;
    NSCalendarDate *refreshDate;
    OWURL *refreshURL, *referringURL;
    OWAddress *refreshAddress;
    OWWebPipeline *refreshPipeline;
    OFStringScanner *scanner;


    refreshTimeString = nil;
    urlString = nil;
    scanner = [[OFStringScanner alloc] initWithString:refresh];
    refreshTimeString = [scanner readFullTokenWithDelimiterCharacter:';'];
    while (scannerPeekCharacter(scanner) == ';') {
        scannerSkipPeekedCharacter(scanner);
        scannerScanUpToCharacterNotInOFCharacterSet(scanner, WhitespaceSet);
        if ([scanner scanStringCaseInsensitive:@"url=" peek:NO]) {
            urlString = [OWURL cleanURLString:[scanner readFullTokenWithDelimiterCharacter:';']];
        } else {
            scannerScanUpToCharacter(scanner, ';');
        }
    }
    [scanner release];
    if (refreshTimeString == nil || [refreshTimeString isEqualToString:@""])
        return;
    referringURL = [(OWAddress *)lastAddress url];
    refreshURL = referringURL;
    if (urlString) {
        if (refreshURL)
            refreshURL = [refreshURL urlFromRelativeString:urlString];
        else
            refreshURL = [OWURL urlFromString:urlString];
    }
    refreshAddress = [OWAddress addressWithURL:refreshURL];
    if (![refreshAddress isSameDocumentAsAddress:(OWAddress *)lastAddress]) {
        // If we've been asked to redirect to another page, we need to make sure we redirect on schedule the next time we load this page.
        // TODO: Rather than flushing our content from the cache, it would be much better to cache the HTTP headers so that the next pipeline gets the cached headers and content rather than having to start again from scratch.
#warning deal with refresh headers effect on cache
//        [[self contentCacheForLastAddress] flushCachedContent];
    }
    refreshTimeInterval = [refreshTimeString floatValue];
    refreshPipeline = [[[self class] alloc] initWithContent:refreshAddress target:[self target]];
    // TODO: Why are we calling -setProxyCacheDisabled:YES here? [wiml]
    [refreshPipeline setProxyCacheDisabled:YES];
    refreshDate = [[NSCalendarDate alloc] initWithTimeIntervalSinceNow:refreshTimeInterval];
    [refreshDate setCalendarFormat:@"%b %d %H:%M:%S"];
    [refreshPipeline setContextObject:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Timed Refresh at %@", @"OWF", [OWWebPipeline bundle], @"webpipeline timed refresh message"), refreshDate] forKey:@"Status"];
    if (referringURL)
        [refreshPipeline setReferringAddress:[OWAddress addressWithURL:referringURL]];
    if (refreshTimeInterval <= 1.0) {
        [refreshPipeline startProcessingContent];
    } else {
        OFScheduledEvent *event;
        
        event = [refreshScheduler scheduleSelector:@selector(startProcessingContent) onObject:refreshPipeline withObject:nil atDate:refreshDate];
        [refreshPipeline _setRefreshEvent:event];
        [refreshPipeline setHistoryAction:OWWebPipelineReloadHistoryAction];
    }
    [refreshDate release];
    [refreshPipeline release];
}

#endif

@end
