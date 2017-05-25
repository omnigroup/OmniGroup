// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/OBObject.h>

@class NSArray, NSDate, NSMutableArray;
@class ONHostAddress, ONServiceEntry;

#import <Foundation/NSDate.h> // For NSTimeInterval

@interface ONHost : OBObject

+ (void)setResolverType:(NSString *)resolverType;

/* Calling this method causes ONHost to track changes to the host's name and domain name (as returned by +domainName and +localHostname). ONHost will register in the calling thread's run loop the first time this method is called. Calling it multiple times has no effect. */
+ (void)listenForNetworkChanges;

/* Returns the local host's domain name. If the domain name is unavailable for some reason, returns the string "local". In some contexts it may be necessary to append a trailing dot to the domain name returned by this method for it to be interpreted correctly by other routines; see RFC1034 [3.1] (page 8). */
+ (NSString *)domainName;

/* Returns the local host's name, if available, or returns "localhost". */
+ (NSString *)localHostname;

+ (ONHost *)hostForHostname:(NSString *)aHostname;
+ (ONHost *)hostForAddress:(ONHostAddress *)anAddress;

+ (NSString *)IDNEncodedHostname:(NSString *)aHostname;
+ (NSString *)IDNDecodedHostname:(NSString *)anIDNHostname;

+ (void)flushCache;
+ (void)setDefaultTimeToLiveTimeInterval:(NSTimeInterval)newValue;

/* Determines whether ONHost tries to look up 'AAAA' records as well as 'A' records. At the moment this has no effect on the actual lookup, but prevents non-IPv4 addresses from being returned by ONHost's -addresses method. */
+ (void)setOnlyResolvesIPv4Addresses:(BOOL)v4Only;
+ (BOOL)onlyResolvesIPv4Addresses;

- (NSString *)hostname;
- (NSArray *)addresses;
- (NSString *)canonicalHostname;
- (NSString *)IDNEncodedHostname;
- (NSString *)domainName;

- (BOOL)isLocalHost;

- (void)flushFromHostCache;

/* Returns an array of ONPortAddresses corresponding to a given service of the receiver's host. Somewhat buggy at the moment. */
- (NSArray *)portAddressesForService:(ONServiceEntry *)servEntry;

@end

// Exceptions which may be raised by this class
extern NSString * const ONHostNotFoundExceptionName;
extern NSString * const ONHostNameLookupErrorExceptionName;
extern NSString * const ONHostHasNoAddressesExceptionName;
