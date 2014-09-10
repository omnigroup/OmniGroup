// Copyright 2010, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// OmniFoundation changes:
//   - formatting, and minor cleanup from the base Apple version

/*

===== IMPORTANT =====

This is sample code demonstrating API, technology or techniques in development.
Although this sample code has been reviewed for technical accuracy, it is not
final. Apple is supplying this information to help you plan for the adoption of
the technologies and programming interfaces described herein. This information
is subject to change, and software implemented based on this sample code should
be tested with final operating system software and final documentation. Newer
versions of this sample code may be provided with future seeds of the API or
technology. For information about updates to this and other developer
documentation, view the New & Updated sidebars in subsequent documentation
seeds.

=====================

File: NetReachability.m
Abstract: Convenience class that wraps the SCNetworkReachability APIs from
SystemConfiguration.

Version: 1.1

Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple Inc.
("Apple") in consideration of your agreement to the following terms, and your
use, installation, modification or redistribution of this Apple software
constitutes acceptance of these terms.  If you do not agree with these terms,
please do not use, install, modify or redistribute this Apple software.

In consideration of your agreement to abide by the following terms, and subject
to these terms, Apple grants you a personal, non-exclusive license, under
Apple's copyrights in this original Apple software (the "Apple Software"), to
use, reproduce, modify and redistribute the Apple Software, with or without
modifications, in source and/or binary forms; provided that if you redistribute
the Apple Software in its entirety and without modifications, you must retain
this notice and the following text and disclaimers in all such redistributions
of the Apple Software.
Neither the name, trademarks, service marks or logos of Apple Inc. may be used
to endorse or promote products derived from the Apple Software without specific
prior written permission from Apple.  Except as expressly stated in this notice,
no other rights or licenses, express or implied, are granted by Apple herein,
including but not limited to any patent rights that may be infringed by your
derivative works or by other works in which the Apple Software may be
incorporated.

The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
COMBINATION WITH YOUR PRODUCTS.

IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR
DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF
CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF
APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Copyright (C) 2008 Apple Inc. All Rights Reserved.

*/

#import <OmniFoundation/OFNetReachability.h>

#import <SystemConfiguration/SCNetworkReachability.h>
#import <netinet/in.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#endif

RCS_ID("$Id$")

//MACROS:

#if TARGET_OS_IPHONE
    #define IS_REACHABLE(__FLAGS__) (((__FLAGS__) & kSCNetworkReachabilityFlagsReachable) && !((__FLAGS__) & kSCNetworkReachabilityFlagsConnectionRequired))
    #if TARGET_IPHONE_SIMULATOR
        #define IS_CELL(__FLAGS__) (0)
    #else
        #define IS_CELL(__FLAGS__) (((__FLAGS__) & kSCNetworkReachabilityFlagsReachable) && ((__FLAGS__) & kSCNetworkReachabilityFlagsIsWWAN))
    #endif
#else
    #define IS_REACHABLE(__FLAGS__) (((__FLAGS__) & kSCNetworkFlagsReachable) && !((__FLAGS__) & kSCNetworkFlagsConnectionRequired))
    #define IS_CELL(__FLAGS__) (0)
#endif

//CLASS IMPLEMENTATION:

@implementation OFNetReachability

+ (void)initialize;
{
    OBINITIALIZE;
    
#if defined(OMNI_ASSERTIONS_ON) && (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE)
    if ([[NSProcessInfo processInfo] isSandboxed]) {
        // Sandboxed Mac applications cannot talk to the network by default. Give a better hint about why stuff is failing than reachability silently always being false.
        NSDictionary *entitlements = [[NSProcessInfo processInfo] codeSigningEntitlements];
        OBASSERT([entitlements[@"com.apple.security.network.client"] boolValue]);
    }
#endif
}

static void _ReachabilityCallBack(SCNetworkReachabilityRef target, SCNetworkConnectionFlags flags, void* info)
{
    @autoreleasepool {
        OFNetReachability *self = (__bridge OFNetReachability *)info;
        [self->_delegate reachabilityDidUpdate:self reachable:(IS_REACHABLE(flags) ? YES : NO) usingCell:(IS_CELL(flags) ? YES : NO)];
    }
}

@synthesize delegate = _delegate;

/*
This will consume a reference of "reachability"
*/
- (id)_initWithNetworkReachability:(SCNetworkReachabilityRef)reachability;
{
    if (reachability == NULL) {
        [self release];
        return nil;
    }
    
    if (!(self = [super init]))
        return nil;
    
    _runLoop = (CFRunLoopRef)CFRetain(CFRunLoopGetCurrent());
    _netReachability = (void *)reachability;
    
    return self;
}

- (id)initWithDefaultRoute:(BOOL)ignoresAdHocWiFi;
{
    return [self initWithIPv4Address:(ignoresAdHocWiFi ? INADDR_ANY : IN_LINKLOCALNETNUM)];
}

- (id)initWithAddress:(const struct sockaddr *)address;
{
    SCNetworkReachabilityRef reachability = NULL;
    if (address)
        reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, address);
    
    return [self _initWithNetworkReachability:reachability];
}

- (id)initWithIPv4Address:(UInt32)address;
{
    struct sockaddr_in ipAddress = {0};
    
    ipAddress.sin_len = sizeof(ipAddress);
    ipAddress.sin_family = AF_INET;
    ipAddress.sin_addr.s_addr = htonl(address);
    
    return [self initWithAddress:(struct sockaddr *)&ipAddress];
}

- (id)initWithHostName:(NSString *)name;
{
    SCNetworkReachabilityRef reachability = NULL;
    if (![NSString isEmptyString:name])
        reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [name UTF8String]);
    
    return [self _initWithNetworkReachability:reachability];
}

- (void)dealloc;
{
    [self setDelegate:nil];
    
    if (_runLoop)
	CFRelease(_runLoop);
    if (_netReachability)
	CFRelease(_netReachability);
    
    [super dealloc];
}

- (BOOL)isReachable;
{
    SCNetworkConnectionFlags flags;
    if (!SCNetworkReachabilityGetFlags(_netReachability, &flags))
        return NO;
    
    return IS_REACHABLE(flags) ? YES : NO;
}

- (BOOL)isUsingCell;
{
    SCNetworkConnectionFlags flags;
    if (!SCNetworkReachabilityGetFlags(_netReachability, &flags))
        return NO;
    
    return IS_CELL(flags) ? YES : NO;
}

- (void)setDelegate:(id <OFNetReachabilityDelegate>)delegate;
{
    if (delegate && !_delegate) {
        SCNetworkReachabilityContext context = {0, self, NULL, NULL, NULL};
        
        if (SCNetworkReachabilitySetCallback(_netReachability, _ReachabilityCallBack, &context)) {
            if (!SCNetworkReachabilityScheduleWithRunLoop(_netReachability, _runLoop, kCFRunLoopCommonModes)) {
                SCNetworkReachabilitySetCallback(_netReachability, NULL, NULL);
                delegate = nil;
            }
        } else
            delegate = nil;
        
        if (delegate == nil)
            NSLog(@"Failed installing SCNetworkReachability callback on runloop %p", _runLoop);
    } else if (!delegate && _delegate) {
        SCNetworkReachabilityUnscheduleFromRunLoop(_netReachability, _runLoop, kCFRunLoopCommonModes);
        SCNetworkReachabilitySetCallback(_netReachability, NULL, NULL);
    }
    
    _delegate = delegate;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@:%p reachable:%i>", NSStringFromClass([self class]), self, [self isReachable]];
}

@end
