// Copyright 1997-2005, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWHTTPProcessor.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSDate-OWExtensions.h"
#import "OWAddress.h"
#import "OWCacheControlSettings.h"
#import "OWContent.h"
#import "OWContentType.h"
#import "OWDataStream.h"
#import "OWHeaderDictionary.h"
#import "OWHTTPSessionQueue.h"
#import "OWProxyServer.h"
#import "OWURL.h"

RCS_ID("$Id$")

@implementation OWHTTPProcessor

// Class variables
static NSSet *nonEntityHeaderNames;

+ (void)didLoad;
{
    [self registerProcessorClass:self fromContentType:[OWURL contentTypeForScheme:@"http"] toContentType:[OWContentType wildcardContentType] cost:1.0f producingSource:YES];
}

+ (void)initialize
{
    CFSetRef headerNames;
#define HEADER_NAME_MAX 25
    int count;
    NSString *nonEntityHeaderNameArray[HEADER_NAME_MAX];
    
    OBINITIALIZE;

    count = 0;
//  TODO: Handle 'Age' appropriately
    nonEntityHeaderNameArray[count++] = @"Authorization";
    nonEntityHeaderNameArray[count++] = @"Connection";
    nonEntityHeaderNameArray[count++] = @"Date";
    nonEntityHeaderNameArray[count++] = @"Keep-Alive";
    nonEntityHeaderNameArray[count++] = @"Location";  // Different from Content-Location. The Location field is stripped out earlier and used to genenerate a redirection content.
    nonEntityHeaderNameArray[count++] = @"Proxy-Authenticate";
    nonEntityHeaderNameArray[count++] = @"Proxy-Authorization";
    nonEntityHeaderNameArray[count++] = @"Retry-After";
    nonEntityHeaderNameArray[count++] = @"Set-Cookie";    // Nonstandard but widely used
    nonEntityHeaderNameArray[count++] = @"Set-Cookie2";   // Nonstandard but widely used
    nonEntityHeaderNameArray[count++] = @"TE";
    nonEntityHeaderNameArray[count++] = @"Transfer-Encoding";
    nonEntityHeaderNameArray[count++] = @"Upgrade";
    
    // Other random stuff
    nonEntityHeaderNameArray[count++] = @"Proxy-Connection";
    nonEntityHeaderNameArray[count++] = @"X-Cache";
    nonEntityHeaderNameArray[count++] = @"X-Cache-Lookup";

    // The following headers should really be used to add properties to the arc, rather than left on the OWContent. For now they're on the OWContent.
 //  nonEntityHeaderNameArray[count++] = @"Accept-Ranges";  // Currently this needs to be on the content because that's where OHDownloader looks for it. It should probably be on the arc, because it's an attribute of the server's ability to supply this content, not an attribute of the content itself.
 //    nonEntityHeaderNameArray[count++] = @"Server";
 //    nonEntityHeaderNameArray[count++] = @"Vary";
 //    nonEntityHeaderNameArray[count++] = @"Via";
 //    nonEntityHeaderNameArray[count++] = @"X-Cache";    // Nonstandard but widely used

    assert(count <= HEADER_NAME_MAX);

    headerNames = CFSetCreate(kCFAllocatorDefault, (const void **)nonEntityHeaderNameArray, count, &OFCaseInsensitiveStringSetCallbacks);
    nonEntityHeaderNames = (NSSet *)headerNames;
}

+ (BOOL)processorUsesNetwork
{
    return YES;
}

// Init and dealloc

- (void)dealloc;
{
    [dataStream release];
    [httpContent release];
    [queue release];
    [credentials release];
    [super dealloc];
}

// API

- (Class)sessionQueueClass;
{
    return [OWHTTPSessionQueue class];
}

- (void)startProcessingInHTTPSessionQueue:(OWHTTPSessionQueue *)aQueue;
{
    OBPRECONDITION(queue == nil);
    
    queue = [aQueue retain];
    if ([queue queueProcessor:self])
        [super startProcessing];
}

- (void)handleSessionException:(NSException *)anException;
{
    if (status != OWProcessorAborting)
        [self handleProcessingException:anException];
    [self processAbort];
}

- (OWDataStream *)dataStream;
{
    return dataStream;
}

- (void)setDataStream:(OWDataStream *)aDataStream;
{
    if (aDataStream != dataStream) {
        [dataStream release];
        dataStream = [aDataStream retain];
        [httpContent release];
        httpContent = [[OWContent contentWithDataStream:dataStream isSource:YES] retain];
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
            [pipeline mightAffectResource:anAffectedResource];
    });
    [affectedLocations release];
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

    [pipeline cacheControl:[OWCacheControlSettings cacheSettingsForHeaderDictionary:headerDict]];
}

- (void)markEndOfHeaders;
{
    [httpContent markEndOfHeaders];
}

- (void)addContent;
{
    [pipeline addContent:[self content] fromProcessor:self flags:httpContentFlags];
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
    
    [credentials release];
    credentials = [newCredentials copy];

    [newCredentials release];
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
    NSString *reqMethod;
    
    httpContentFlags = OWProcessorContentIsSource|OWProcessorTypeRetrieval;
    
    // Decide whether the URL is probably an 'operation' instead of a 'retrieval'.
    reqMethod = [sourceAddress methodString];
    if ([reqMethod isEqualToString:@"GET"] || [reqMethod isEqualToString:@"HEAD"]) {
        // GETs are generally retrievals, unless they have a query-string [9.1],[13.9]. 
        if (![NSString isEmptyString:[[sourceAddress url] query]])
            httpContentFlags |= OWProcessorTypeAction;
    } else if ([reqMethod isEqualToString:@"OPTIONS"]) {
        // OPTIONS isn't an action. It's not cacheable, though. [9.2]
        [pipeline cacheControl:[OWCacheControlSettings cacheSettingsWithNoCache]];
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
        if (status != OWProcessorAborting)
            [self handleProcessingException:localException];
        [self processAbort];
        [self retire];
    } NS_ENDHANDLER;
}

- (void)processBegin;
{
    [super processBegin];
    if (httpContentFlags & OWProcessorTypeAction)
        [pipeline mightAffectResource:[sourceAddress url]];
}

- (void)processInThread;
{
    [queue runSession];
}

- (void)abortProcessing;
{
    [self retain];
    OWHTTPSessionQueue *myQueue = [[queue retain] autorelease];
    [super abortProcessing];
    [myQueue abortProcessingForProcessor:self];
    if (dataStream && ![dataStream endOfData])
        [dataStream dataAbort];
    [self markEndOfHeaders];
    [self release];
}

@end

