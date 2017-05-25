// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/ONServiceEntry.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniBase/system.h>

RCS_ID("$Id$")

@implementation ONServiceEntry
{
    NSString *serviceName;
    NSString *protocolName;
    int portNumber;
}

static NSRecursiveLock *serviceLookupLock;
static NSMutableDictionary *serviceCache;
static NSMutableDictionary *portHints;

+ (void)initialize;
{
    OBINITIALIZE;

    serviceLookupLock = [[NSRecursiveLock alloc] init];
    serviceCache = [[NSMutableDictionary alloc] initWithCapacity:4];
    portHints = nil;
}

+ (ONServiceEntry *)httpService
{
    return [self serviceEntryNamed:@"http" protocolName:ONServiceEntryTCPProtocolName];
}

+ (ONServiceEntry *)smtpService;
{
    return [self serviceEntryNamed:@"smtp" protocolName:ONServiceEntryTCPProtocolName];
}

+ serviceEntryNamed:(NSString *)aServiceName protocolName:(NSString *)aProtocolName;
{
    ONServiceEntry *entry = nil;
    struct servent *newServiceEntry;
    NSMutableDictionary *protocolDictionary;

    if (!aServiceName || !aProtocolName)
	return nil;

    [serviceLookupLock lock];

    if (!(protocolDictionary = [serviceCache objectForKey:aProtocolName])) {
	protocolDictionary = [[NSMutableDictionary alloc] init];
	[serviceCache setObject:protocolDictionary forKey:aProtocolName];
	[protocolDictionary release];
    }
    entry = [protocolDictionary objectForKey:aServiceName];
    if (!entry) {
        const char *cServiceName, *cProtocolName;
        NSString *canonicalName;

        cServiceName = [aServiceName cStringUsingEncoding:NSASCIIStringEncoding];
        cProtocolName = [aProtocolName cStringUsingEncoding:NSASCIIStringEncoding];

        newServiceEntry = getservbyname(cServiceName, cProtocolName);
        if (newServiceEntry) {
            if (strcmp(newServiceEntry->s_name, cServiceName) != 0)
                canonicalName = [NSString stringWithUTF8String:newServiceEntry->s_name];
            else
                canonicalName = aServiceName;

            /* If we've just looked up an alias, get the ONServiceEntry  from the canonical name */
            if ([protocolDictionary objectForKey:canonicalName] != nil)
                entry = [[protocolDictionary objectForKey:canonicalName] retain];
            else {
                entry = [[self alloc] _initWithServiceName:canonicalName protocolName:aProtocolName port:ntohs(newServiceEntry->s_port)];
                [protocolDictionary setObject:entry forKey:canonicalName];
            }

            /* store the entry under the name we just looked it up by */
            [protocolDictionary setObject:entry forKey:aServiceName];

            /* store the entry under any aliases it has */
            if (newServiceEntry->s_aliases) {
                int aliasIndex = 0;
                for (aliasIndex = 0; newServiceEntry->s_aliases[aliasIndex] != NULL; aliasIndex ++) {
                    NSString *serviceNameAlias = [NSString stringWithUTF8String:newServiceEntry->s_aliases[aliasIndex]];
                    if (![protocolDictionary objectForKey:serviceNameAlias])
                        [protocolDictionary setObject:entry forKey:serviceNameAlias];
                }
            }
            
            [entry release];
        } else if (portHints != nil) {
            NSString *fallbackCacheKey;
            NSNumber *fallbackPort;
            
            fallbackCacheKey = [NSString stringWithFormat:@"%@/%@", aServiceName, aProtocolName];
            fallbackPort = [portHints objectForKey:fallbackCacheKey];
            if (fallbackPort != nil) {
                entry = [[self alloc] _initWithServiceName:aServiceName protocolName:aProtocolName port:[fallbackPort intValue]];
                [protocolDictionary setObject:entry forKey:aServiceName];
                [entry release];
            }
        }
            
    }

    [serviceLookupLock unlock];

    if (!entry)
	[NSException raise:ONServiceNotFoundExceptionName format:@"Service/Protocol '%@/%@' not found", aServiceName, aProtocolName];

    return entry;
}

+ (void)hintPort:(int)aPortNumber forServiceNamed:(NSString *)aServiceName protocolName:(NSString *)aProtocolName
{
    NSMutableDictionary *protocolDictionary;
    NSString *cacheKey;

    if (!aServiceName || !aProtocolName || !aPortNumber)
        return;

    cacheKey = [NSString stringWithFormat:@"%@/%@", aServiceName, aProtocolName];

    [serviceLookupLock lock];
    if ((protocolDictionary = [serviceCache objectForKey:aProtocolName]) != nil) {
        if ([protocolDictionary objectForKey:aServiceName]) {
            [serviceLookupLock lock];
            return;
        }
    }
    if (portHints == nil)
        portHints = [[NSMutableDictionary alloc] init];
    [portHints setObject:[NSNumber numberWithInt:aPortNumber] forKey:cacheKey];
    [serviceLookupLock unlock];
}

- (void)dealloc;
{
    [serviceName release];
    [protocolName release];
    [super dealloc];
}

- (NSString *)serviceName;
{
    return serviceName;
}

- (NSString *)protocolName;
{
    return protocolName;
}

- (unsigned short int)portNumber;
{
    return portNumber;
}

- (NSUInteger)hash
{
    return [serviceName hash] ^ [protocolName hash];
}

- (BOOL)isEqual:(ONServiceEntry *)anotherEntry
{
    if (![anotherEntry isKindOfClass:[self class]])
        return NO;

    if ([anotherEntry portNumber] != [self portNumber] ||
        ![[anotherEntry serviceName] isEqual:serviceName] ||
        ![[anotherEntry protocolName] isEqual:protocolName])
        return NO;

    return YES;
}

- (id)copyWithZone:(NSZone *)zone;
{
    // We're an immutable data-holder; we can copy by reference
    return [self retain];
}

#pragma mark - Private

- _initWithServiceName:(NSString *)aServiceName protocolName:(NSString *)aProtocolName port:(int)aPortNumber;
{
    if (!(self = [super init]))
        return nil;

    serviceName = [aServiceName copy];
    protocolName = [aProtocolName copy];
    portNumber = aPortNumber;

    return self;
}

@end

NSString * const ONServiceEntryIPProtocolName = @"ip";
NSString * const ONServiceEntryICMPProtocolName = @"icmp";
NSString * const ONServiceEntryTCPProtocolName = @"tcp";
NSString * const ONServiceEntryUDPProtocolName = @"udp";

NSString * const ONServiceNotFoundExceptionName = @"ONServiceNotFoundExceptionName";
