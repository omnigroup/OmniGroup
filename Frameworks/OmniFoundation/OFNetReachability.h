// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
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

File: NetReachability.h
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

#import <Foundation/NSObject.h>
#import <sys/socket.h>

//CLASSES:

@class OFNetReachability;

//PROTOCOLS:

@protocol OFNetReachabilityDelegate <NSObject>
- (void)reachabilityDidUpdate:(OFNetReachability *)reachability reachable:(BOOL)reachable usingCell:(BOOL)usingCell;
@end

//CLASS INTERFACES:

/*
 This class wraps the SCNetworkReachability APIs from SystemConfiguration, which tell you whether or not the system has a route to a given host.
 Be aware that reachability doesn't guarantee you can get somewhere, it just lets you know when we can guarantee you won't get there.
 If you only care about reachability of given host, use -initWithAddress:, -initWithIPv4Address: or -initWithHostName:.
 If you care about reachability in general (i.e. is network active or not), use -initWithDefaultRoute:.
 In both cases, use the "usingCell" parameter to know if reachability is achieved over WiFi or cell connection (e.g. Edge).
 */
@interface OFNetReachability : NSObject
{
@private
    void *_netReachability;
    CFRunLoopRef _runLoop;
    id <OFNetReachabilityDelegate> _delegate;
}

- (id)initWithDefaultRoute:(BOOL)ignoresAdHocWiFi; // If both Cell and Ad-Hoc WiFi are available and "ignoresAdHocWiFi" is YES, "usingCell" will still return YES

- (id)initWithAddress:(const struct sockaddr *)address;
- (id)initWithIPv4Address:(UInt32)address; // The "address" is assumed to be in host-endian
- (id)initWithHostName:(NSString *)name;

@property(nonatomic,assign) id <OFNetReachabilityDelegate> delegate;

@property(readonly, getter=isReachable) BOOL reachable;
@property(readonly, getter=isUsingCell) BOOL usingCell; // Only valid if "isReachable" is YES

@end
