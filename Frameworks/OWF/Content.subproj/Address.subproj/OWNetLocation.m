// Copyright 1999-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWNetLocation.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation OWNetLocation

+ (OWNetLocation *)netLocationWithString:(NSString *)aNetLocation;
{
    NSString *netLocation;
    NSString *aUsername = nil, *aPassword = nil;
    NSString *aHostname = nil, *aPort = nil;
    NSRange separator;

    if (aNetLocation == nil)
	return nil;
    netLocation = aNetLocation;
    if ((separator = [netLocation rangeOfString:@"@" options:NSBackwardsSearch]).length > 0) {
	aUsername = [netLocation substringToIndex:separator.location];
	netLocation = [netLocation substringFromIndex:NSMaxRange(separator)];
	if ((separator = [aUsername rangeOfString:@":"]).length > 0) {
	    aPassword = [aUsername substringFromIndex:NSMaxRange(separator)];
            aUsername = [aUsername substringToIndex:separator.location];
	}
    }

    // Check for an address literal a la RFC 2732 (which is just a kludge to support the poor choice of IPv6 literal syntax, but we have to live with it now.)
    if ([netLocation hasPrefix:@"["]) {
        NSRange closeBracket = [netLocation rangeOfString:@"]"];
        if (closeBracket.length > 0) {
            if (NSMaxRange(closeBracket) == [netLocation length]) {
                aHostname = netLocation;
                aPort = nil;
            } else if (NSMaxRange(closeBracket) < [netLocation length] &&
                       [netLocation characterAtIndex:NSMaxRange(closeBracket)] == ':') {
                aHostname = [netLocation substringToIndex:NSMaxRange(closeBracket)];
                aPort = [netLocation substringFromIndex:NSMaxRange(closeBracket) + 1];
            }
            // We found a bracketed string, but there seems to be some trailing garbage. Fall back to earlier syntax.
        }
    }

    // Not extracting an address literal; just split on a colon (the last one, if multiple)
    if (aHostname == nil) {
        separator = [netLocation rangeOfString:@":" options:NSBackwardsSearch];
        if (separator.length) {
            aHostname = [netLocation substringToIndex:separator.location];
            aPort = [netLocation substringFromIndex:NSMaxRange(separator)];
        } else {
            aHostname = netLocation;
            aPort = nil;
        }
    }

    aUsername = aUsername ? [NSString decodeURLString:aUsername] : nil;
    aPassword = aPassword ? [NSString decodeURLString:aPassword] : nil;
//    aHostname = [NSString decodeURLString:aHostname];
    aPort     = [NSString decodeURLString:aPort];
        
    return [[self alloc] initWithUsername:aUsername password:aPassword hostname:aHostname port:aPort];
}

// Init and dealloc

- initWithUsername:(NSString *)aUsername password:(NSString *)aPassword hostname:(NSString *)aHostname port:(NSString *)aPort;
{
    if (!(self = [super init]))
	return nil;

    /* Empty usernames/passwords are possible, and are distinct from having no username or password ... */
    username = aUsername;
    password = aPassword;
    /* ... but an empty hostname or port is the same as having no hostname or port. To simplify logic elsewhere in this class, we guarantee that hostname is non-nil, and we guarantee that port is non-nil if and only if it is non-empty.  */
    hostname = [NSString isEmptyString:aHostname] ? @"" : aHostname;
    port     = [NSString isEmptyString:aPort] ? nil : aPort;

    return self;
}

// Access methods

- (NSString *)username;
{
    return username;
}

- (NSString *)password;
{
    return password;
}

- (NSString *)hostname;
{
    return hostname;
}

- (NSString *)port;
{
    // port is guaranteed to be non-empty if it is non-nil; see explanation in -init:
    OBINVARIANT(port == nil || ![NSString isEmptyString:port]);
    return port;
}

- (NSString *)hostnameWithPort;
{
    if (port == nil)
        return hostname;
    else
        return [NSString stringWithStrings:hostname, @":", port, nil];
}

// API

- (NSString *)displayString;
{
    NSMutableString *displayString;

    OBINVARIANT(hostname != nil);

    // Common case.
    if (username == nil && password == nil && port == nil /* && hostname != nil */)
        return hostname;

    // General case.
    displayString = [NSMutableString stringWithCapacity:[hostname length]];
    if (username) {
	[displayString appendString:username];
	if (password)
	    [displayString appendStrings:@":", password, nil];
	[displayString appendString:@"@"];
    }
    [displayString appendString:hostname];
    if (port)
	[displayString appendStrings:@":", port, nil];
    return displayString;
}

- (NSString *)shortDisplayString;
{
    if (!shortDisplayName) {
        NSRange useableRange;
        NSString *implicitSuffix, *implicitPrefix;
        NSUInteger implicitPrefixLength;
        
        implicitSuffix = NSLocalizedStringFromTableInBundle(@".com", @"OWF", [OWNetLocation bundle], @"netlocation string to remove from addresses when displaying them in short form");
        implicitPrefix = @"www.";

        useableRange = NSMakeRange(0, [hostname length]);
        if ([hostname hasSuffix:implicitSuffix])
            useableRange.length -= [implicitSuffix length];
        implicitPrefixLength = [implicitPrefix length];
        if (useableRange.length > implicitPrefixLength && [hostname hasPrefix:implicitPrefix]) {
            useableRange.location += implicitPrefixLength;
            useableRange.length -= implicitPrefixLength;
        }

        shortDisplayName = [hostname substringWithRange:useableRange];
    }
    return shortDisplayName;
}

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    if (username)
	[debugDictionary setObject:username forKey:@"username"];
    if (password)
	[debugDictionary setObject:password forKey:@"password"];
    if (hostname)
	[debugDictionary setObject:hostname forKey:@"hostname"];
    if (port)
	[debugDictionary setObject:port forKey:@"port"];

    return debugDictionary;
}

- (NSString *)shortDescription;
{
    return [self displayString];
}

@end
