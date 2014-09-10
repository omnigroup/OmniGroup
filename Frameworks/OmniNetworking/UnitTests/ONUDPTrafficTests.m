// Copyright 2003-2006, 2010-2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniNetworking/OmniNetworking.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <XCTest/XCTest.h>
#include <unistd.h>
#include <sys/socket.h>

RCS_ID("$Id$");

const char *s1 = "This is some test data.";
const char *s2 = "This is also some test data. It's a bit longer.";
#define S3_LEN (1040)
const char *s4 = "Would you like another packet? It is WAFFER THIN!";

@interface ONUDPTrafficTests : XCTestCase
{
    int addressFamily;
    
    ONUDPSocket *huey, *dewie, *louie;

    char s3[S3_LEN];
}

@end

@implementation ONUDPTrafficTests

// Init and dealloc

- (id) initWithInvocation:(NSInvocation *) anInvocation;
{
    self = [super initWithInvocation:anInvocation];
    addressFamily = AF_UNSPEC;
    return self;
}

- (void)setUp;
{
    huey = [(ONUDPSocket *)[ONUDPSocket socket] retain];
    dewie = [(ONUDPSocket *)[ONUDPSocket socket] retain];
    louie = [(ONUDPSocket *)[ONUDPSocket socket] retain];

    if (addressFamily != AF_UNSPEC) {
        [huey setAddressFamily:addressFamily];
        [dewie setAddressFamily:addressFamily];
        [louie setAddressFamily:addressFamily];
    }
}

- (void)dealloc;
{
    [huey release];
    [dewie release];
    [louie release];
    [super dealloc];
}

- (ONHostAddress *)loopback
{
    if (addressFamily == AF_UNSPEC)
        return [ONHostAddress loopbackAddress];
    else if (addressFamily == AF_INET)
        return [ONHostAddress hostAddressWithNumericString:@"127.0.0.1"];
    else if (addressFamily == AF_INET6)
        return [ONHostAddress hostAddressWithNumericString:@"::1"];
    else
        return nil;
}

- (void)testUDPLoopback
{
    ONPortAddress *addrD, *addrDLoop;
    NSData *rd;
    
    XCTAssertFalse([dewie isConnected]);
    [dewie setLocalPortNumber];

    addrD = [[ONPortAddress alloc] initWithHostAddress:[self loopback] portNumber:[dewie localAddressPort]];
    XCTAssertTrue(addrD != nil);
    [addrD autorelease];

    XCTAssertFalse([dewie isConnected]);
    XCTAssertTrue([dewie remoteAddress] == nil);

    size_t len = [dewie writeBytes:strlen(s4) fromBuffer:s4 toPortAddress:addrD];
    XCTAssertTrue(len == strlen(s4));

    XCTAssertFalse([dewie isConnected]);
    XCTAssertTrue([dewie remoteAddress] == nil);

    rd = [dewie readData];
    XCTAssertFalse([dewie isConnected]);
    XCTAssertTrue([dewie remoteAddress] != nil);
    addrDLoop = [dewie remoteAddress];

    if (rd == nil) {
        XCTAssertTrue(rd != nil);
    } else {
        XCTAssertTrue([rd length] == len);
        XCTAssertTrue(memcmp([rd bytes], s4, len) == 0);
    }

    // NSLog(@"Sent to: %@ Received from: %@", addrD, addrDLoop);
    XCTAssertTrue([addrDLoop isEqual:addrD]);
}

- (void)testConnectedUDP
{
    ONPortAddress *addrH, *addrL;
    size_t len, res;
    NSData *rd;

    XCTAssertTrue(huey != nil);
    XCTAssertTrue(louie != nil);

    [huey setLocalPortNumber];
    [louie setLocalPortNumber];
    addrH = [huey localAddress];
    addrL = [louie localAddress];

    XCTAssertFalse(addrH == nil);
    XCTAssertFalse(addrL == nil);
    XCTAssertFalse([addrH isEqual:addrL]);
    XCTAssertFalse([huey localAddressPort] == [louie localAddressPort]);

    XCTAssertFalse([huey isConnected]);
    [huey connectToAddress:[self loopback] port:[louie localAddressPort]];
    XCTAssertTrue([huey isConnected]);
    XCTAssertFalse([louie isConnected]);
    [louie connectToAddress:[self loopback] port:[huey localAddressPort]];
    XCTAssertTrue([louie isConnected]);
    XCTAssertTrue([huey isConnected]);
    /* The host parts won't typically be the same because they'll be bound to the wildcard address locally and the loopback address remotely. So just check the port numbers. */
    XCTAssertTrue([huey localAddressPort] == [louie remoteAddressPort]);
    XCTAssertTrue([louie localAddressPort] == [huey remoteAddressPort]);
    // NSLog(@"Huey: local=%@ remote=%@", [huey localAddress], [huey remoteAddress]);
    // NSLog(@"Louie: local=%@ remote=%@", [louie localAddress], [louie remoteAddress]);

    len = strlen(s1);
    res = [huey writeBytes:len fromBuffer:s1];
    XCTAssertTrue(res == len);

    len = strlen(s2);
    res = [louie writeBytes:len fromBuffer:s2];
    XCTAssertTrue(res == len);

    rd = [huey readData];
    if (rd == nil) {
        XCTAssertTrue(rd != nil);
    } else {
        XCTAssertTrue([rd length] == strlen(s2));
        XCTAssertTrue(memcmp([rd bytes], s2, strlen(s2)) == 0);
    }

    rd = [louie readData];
    if (rd == nil) {
        XCTAssertTrue(rd != nil);
    } else {
        XCTAssertTrue([rd length] == strlen(s1));
        XCTAssertTrue(memcmp([rd bytes], s1, strlen(s1)) == 0);
    }
}

- (void)setAddressFamily:(int)af
{
    addressFamily = af;
}

+ (XCTestSuite *)defaultTestSuite;
{
    XCTestSuite *all = [XCTestSuite /* emptyTestSuiteForTestCaseClass:self */ testSuiteWithName:[self description]];
    struct { int af; char *n; } variations[3] = { { AF_UNSPEC, "AF_UNSPEC" }, { AF_INET, "AF_INET" }, { AF_INET6, "AF_INET6" } };
    int i;
    
    for(i = 0; i < 3; i++) {
        XCTestSuite *some;
        NSArray *invocations;
        unsigned int invocationIndex;
        int af = variations[i].af;
        
        invocations = [self testInvocations];
        some = [XCTestSuite testSuiteWithName:[NSString stringWithFormat:@"%@ (%s)", [all name], variations[i].n]];
        for(invocationIndex = 0; invocationIndex < [invocations count]; invocationIndex ++) {
            ONUDPTrafficTests *test = [self testCaseWithInvocation:[invocations objectAtIndex:invocationIndex]];
            if (af != AF_UNSPEC)
                [test setAddressFamily:af];
            [some addTest:test];
        }
        [all addTest:some];
    }
    
    return all;
}

@end
