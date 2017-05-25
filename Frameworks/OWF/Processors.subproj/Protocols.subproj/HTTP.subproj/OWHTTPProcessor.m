// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWHTTPProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/NSDate-OWExtensions.h>
#import <OWF/OWAddress.h>
#import <OWF/OWCacheControlSettings.h>
#import <OWF/OWContent.h>
#import <OWF/OWContentType.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWHeaderDictionary.h>
#import <OWF/OWHTTPSessionQueue.h>
#import <OWF/OWProxyServer.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

@implementation OWHTTPProcessor

// Class variables
static NSSet *nonEntityHeaderNames;

OBDidLoad(^{
    Class self = [OWHTTPProcessor class];
    [self registerProcessorClass:self fromContentType:[OWURL contentTypeForScheme:@"http"] toContentType:[OWContentType wildcardContentType] cost:1.0f producingSource:YES];
});

+ (void)initialize
{
    OBINITIALIZE;

//  TODO: Handle 'Age' appropriately
    const void *nonEntityHeaderNameArray[] = {
        @"Authorization",
        @"Connection",
        @"Date",
        @"Keep-Alive",
        @"Location", // Different from Content-Location. The Location field is stripped out earlier and used to genenerate a redirection content.
        @"Proxy-Authenticate",
        @"Proxy-Authorization",
        @"Retry-After",
        @"Set-Cookie", // Nonstandard but widely used
        @"Set-Cookie2", // Nonstandard but widely used
        @"TE",
        @"Transfer-Encoding",
        @"Upgrade",
        
        // Other random stuff
        @"Proxy-Connection",
        @"X-Cache",
        @"X-Cache-Lookup",
        
        // The following headers should really be used to add properties to the arc, rather than left on the OWContent. For now they're on the OWContent.
        // @"Accept-Ranges", // Currently this needs to be on the content because that's where OHDownloader looks for it. It should probably be on the arc, because it's an attribute of the server's ability to supply this content, not an attribute of the content itself.
        // @"Server",
        // @"Vary",
        // @"Via",
        // @"X-Cache", // Nonstandard but widely used
    };
    CFIndex headerNameCount = sizeof(nonEntityHeaderNameArray) / sizeof(*nonEntityHeaderNameArray);
    CFSetRef headerNames = CFSetCreate(kCFAllocatorDefault, nonEntityHeaderNameArray, headerNameCount, &OFCaseInsensitiveStringSetCallbacks);
    nonEntityHeaderNames = CFBridgingRelease(headerNames);
}

+ (BOOL)processorUsesNetwork
{
    return YES;
}

// API

- (Class)sessionQueueClass;
{
    return [OWHTTPSessionQueue class];
}

- (void)startProcessingInHTTPSessionQueue:(OWHTTPSessionQueue *)aQueue;
{
    OBPRECONDITION(queue == nil);
    
    queue = aQueue;
    if ([queue queueProcessor:self])
        [super startProcessing];
}

- (void)handleSessionException:(NSException *)anException;
{
    if (self.status != OWProcessorAborting)
        [self handleProcessingException:anException];
    [self processAbort];
}

- (OWDataStream *)dataStream;
{
    return dataStream;
}

- (void)setDataStream:(OWDataStream *)aDataStream;
{
    if (dataStream != aDataStream) {
        dataStream = aDataStream;
        httpContent = [OWContent contentWithDataStream:dataStream isSource:YES];
        [httpContent addHeader:OWContentHTTPStatusMetadataKey value:[NSNumber numberWithInt:httpStatusCode]];
    }
}

- (void)invalidateForHeaders:(OWHeaderDictionary *)headerDict;
{
    NSMutableArray *affectedLocations;
    NSArray *locations;

    /* RFC2616 --- if we get a response with a Location or Content-Location header, we should bump any resources at those locations out of our cache. (But for security reasons, only if the host-part is the same.) */
    affectedLocations = [[NSMutableArray alloc] init];
    locations = [headerDict stringArrayForKey:@"Content-Location"];
    if (locations)
        [affectedLocations addObjectsFromArray:locations];
    locations = [headerDict stringArrayForKey:@"Location"];
    if (locations)
        [affectedLocations addObjectsFromArray:locations];
    OFForEachInArray(affectedLocations, NSString *, anAffectedLocation, {
        OWURL *anAffectedResource = [[sourceAddress url] urlFromRelativeString:anAffectedLocation];
        if (![anAffectedResource isEqual:[sourceAddress url]] &&
            [[[sourceAddress url] netLocation] isEqual:[anAffectedResource netLocation]])
            [self.pipeline mightAffectResource:anAffectedResource];
    });
}

- (void)addHeaders:(OWHeaderDictionary *)headerDict;
{
    NSEnumerator *headerEnumerator = [headerDict keyEnumerator];
    NSString *headerText;

    while( (headerText = [headerEnumerator nextObject]) != nil ) {
        if ([nonEntityHeaderNames member:headerText])
            continue;
        [httpContent addHeader:headerText values:[headerDict stringArrayForKey:headerText]];
    }

    [self invalidateForHeaders:headerDict];

    [self.pipeline cacheControl:[OWCacheControlSettings cacheSettingsForHeaderDictionary:headerDict]];
}

- (void)markEndOfHeaders;
{
    [httpContent markEndOfHeaders];
}

- (void)addContent;
{
    [self.pipeline addContent:[self content] fromProcessor:self flags:httpContentFlags];
}

- (void)flagResult:(unsigned)someFlags;
{
    httpContentFlags |= someFlags;
}

- (OWContent *)content;
{
    return httpContent;
}

- (unsigned)flags;
{
    return httpContentFlags;
}

- (NSArray *)credentials;
{
    return credentials;
}

- (void)addCredential:(OWAuthorizationCredential *)newCredential;
{
    NSMutableArray *newCredentials = [[NSMutableArray alloc] initWithCapacity: 1 + [credentials count]];

    [newCredentials addObject:newCredential];
    if (credentials)
        [newCredentials addObjectsFromArray:credentials];
    
    credentials = [newCredentials copy];
}

- (void)setHTTPStatusCode:(HTTPStatus)newStatusCode;
{
    httpStatusCode = newStatusCode;
    
    if (httpContent != nil) {
        [httpContent removeHeader:OWContentHTTPStatusMetadataKey];
        [httpContent addHeader:OWContentHTTPStatusMetadataKey value:[NSNumber numberWithInt:httpStatusCode]];
    }
}

// OWProcessor subclass

- (void)startProcessing;
{
    httpContentFlags = OWProcessorContentIsSource|OWProcessorTypeRetrieval;
    
    // Decide whether the URL is probably an 'operation' instead of a 'retrieval'.
    NSString *reqMethod = [sourceAddress methodString];
    if ([reqMethod isEqualToString:@"GET"] || [reqMethod isEqualToString:@"HEAD"]) {
        // GETs are generally retrievals, unless they have a query-string [9.1],[13.9]. 
        if (![NSString isEmptyString:[[sourceAddress url] query]])
            httpContentFlags |= OWProcessorTypeAction;
    } else if ([reqMethod isEqualToString:@"OPTIONS"]) {
        // OPTIONS isn't an action. It's not cacheable, though. [9.2]
        [self.pipeline cacheControl:[OWCacheControlSettings cacheSettingsWithNoCache]];
    } else {
        // Other method strings can be assumed to be actions.
        httpContentFlags |= OWProcessorTypeAction;
    }
    
    NS_DURING {
        if ([[sourceAddress proxyURL] netLocation] == nil) {
            [NSException raise:@"OWHTTPProcessorAddressMissingServer" format:NSLocalizedStringFromTableInBundle(@"The name of the web server is missing from the address '%@'.", @"OWF", [OWHTTPProcessor bundle], @"httpprocessor error - URL does not contain a server address"), [[sourceAddress proxyURL] compositeString]];
        }
        [self startProcessingInHTTPSessionQueue:[[self sessionQueueClass] httpSessionQueueForAddress:sourceAddress]];
    } NS_HANDLER {
        if (self.status != OWProcessorAborting)
            [self handleProcessingException:localException];
        [self processAbort];
        [self retire];
    } NS_ENDHANDLER;
}

- (void)processBegin;
{
    [super processBegin];
    if (httpContentFlags & OWProcessorTypeAction)
        [self.pipeline mightAffectResource:[sourceAddress url]];
}

- (void)processInThread;
{
    [queue runSession];
}

- (void)abortProcessing;
{
    OWHTTPProcessor *strongSelf = self;
    OWHTTPSessionQueue *myQueue = queue;
    OBRetainAutorelease(myQueue);
    [super abortProcessing];
    [myQueue abortProcessingForProcessor:self];
    if (dataStream != nil && ![dataStream endOfData])
        [dataStream dataAbort];
    [self markEndOfHeaders];
    strongSelf = nil;
}

@end

