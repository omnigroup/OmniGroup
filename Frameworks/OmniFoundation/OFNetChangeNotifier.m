// Copyright 2005-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFNetChangeNotifier.h>
#import <OmniFoundation/OFXMLIdentifier.h>

RCS_ID("$Id$");

#if !OF_ENABLE_NET_STATE
#error Should not be in the target
#endif

@implementation OFNetChangeNotifier

#define SEARCH_DOMAIN	    @"local."
#define NET_SERVICE_TYPE    @"_ofchanges._tcp."

- (NSData *)_txtRecordData;
{
    NSString *dateString = [NSString stringWithFormat:@"%f", [lastChangeDate timeIntervalSinceReferenceDate]];
    NSData *dateData = [dateString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *info = [NSDictionary dictionaryWithObject:dateData forKey:@"changed"];
    return [NSNetService dataFromTXTRecordDictionary:info];
}

- (NSDate *)_changeDateForTXTRecordData:(NSData *)data;
{
    NSDictionary *info = [NSNetService dictionaryFromTXTRecordData:data];
    NSData *dateData = [info objectForKey:@"changed"];
    if (!dateData)
	return nil;
	
    NSString *dateString = [[NSString alloc] initWithData:dateData encoding:NSUTF8StringEncoding];
    NSDate *result = [NSDate dateWithTimeIntervalSinceReferenceDate:[dateString doubleValue]];
    [dateString release];
    return result;
}

- initWithUUIDString:(NSString *)aString lastUpdateDate:(NSDate *)anUpdateDate delegate:(id)aDelegate;
{
    if (!(self = [super init]))
        return nil;

    nonretainedDelegate = aDelegate;
    uuidString = [aString retain];
    lastUpdateDate = [anUpdateDate retain];
    watchedServices = [[NSMutableDictionary alloc] init];
    
    browser = [[NSNetServiceBrowser alloc] init];
    [browser setDelegate:self];
    [browser searchForServicesOfType:NET_SERVICE_TYPE inDomain:SEARCH_DOMAIN];
    
    return self;
}

- (void)dealloc;
{
    for (NSString *name in watchedServices) {
	NSNetService *watched = [watchedServices objectForKey:name];
	[watched setDelegate:nil];
	[watched stopMonitoring];
	[watched stop];
    }
    [watchedServices release];
    
    [browser stop];
    [browser setDelegate:nil];
    [browser release];
    
    [notifierService stop];
    [notifierService setDelegate:nil];
    [notifierService release];
    
    [uuidString release];
    [lastChangeDate release];
    [super dealloc];
}

- (void)setLastChangedDate:(NSDate *)aDate;
{
    if ([lastChangeDate isEqual:aDate])
	return;
	
    [lastChangeDate release];
    lastChangeDate = [aDate retain];

    if (!notifierService) {
	NSString *uniqueBit = OFXMLCreateID();
	NSString *serviceName = [NSString stringWithFormat:@"%@:%@", uuidString, uniqueBit];
	[uniqueBit release];
    
	notifierService = [[NSNetService alloc] initWithDomain:SEARCH_DOMAIN type:NET_SERVICE_TYPE name:serviceName port:1234];    
	[notifierService setTXTRecordData:[self _txtRecordData]];
	[notifierService setDelegate:self];
	[notifierService publish];
    } else {
	[notifierService setTXTRecordData:[self _txtRecordData]];
    }
}

- (void)setLastUpdateDate:(NSDate *)aDate;
{
    if (aDate != lastUpdateDate) {
	[lastUpdateDate release];
	lastUpdateDate = [aDate retain];
    }
}

- (void)netServiceDidPublish:(NSNetService *)sender;
{
    //NSLog(@"OFNetChangeNotifier did publish: %@", [sender name]);	    
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict;
{
    //NSLog(@"OFNetChangeNotifier failed publish: %@ = %@", [sender name], errorDict);
}

- (void)netService:(NSNetService *)sender didUpdateTXTRecordData:(NSData *)data;
{
    if (sender == notifierService)
	return;

    //NSLog(@"OFNetChangeNotifier updated txt service: %@", [sender name]);	    
    NSDate *changedDate = [self _changeDateForTXTRecordData:data];
    if (!changedDate || [changedDate compare:lastUpdateDate] != NSOrderedDescending)
	return;
	
    [nonretainedDelegate netChangeNotifierNewChange:self];
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender;
{
    if (sender == notifierService)
	return;

    //NSLog(@"OFNetChangeNotifier resolved service: %@", [sender name]);	
    [sender startMonitoring];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing;
{
    NSString *name = [aNetService name];
        
    if ([name isEqual:[notifierService name]])
	return;
    NSArray *nameParts = [name componentsSeparatedByString:@":"];
    if (nameParts.count != 2 || ![[nameParts objectAtIndex:0] isEqualToString:uuidString])
	return;
	
    //NSLog(@"OFNetChangeNotifier watching service: %@", name);
    [watchedServices setObject:aNetService forKey:name];    
    [aNetService setDelegate:self];
    [aNetService resolveWithTimeout:5.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing;
{
    NSString *name = [aNetService name];
    NSNetService *watched = [watchedServices objectForKey:name];

    if (!watched)
	return;
	
    //NSLog(@"OFNetChangeNotifier removing service: %@", name);	
    [watched setDelegate:nil];
    [watched stopMonitoring];
    [watched stop];
    [watchedServices removeObjectForKey:name];
}

@end
