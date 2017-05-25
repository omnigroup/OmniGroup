// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/OBObject.h>

@interface ONServiceEntry : OBObject <NSCopying>

+ (ONServiceEntry *)httpService;
+ (ONServiceEntry *)smtpService;

+ serviceEntryNamed:(NSString *)aServiceName protocolName:(NSString *)aProtocolName;

+ (void)hintPort:(int)portNumber forServiceNamed:(NSString *)aServiceName protocolName:(NSString *)aProtocolName;

- (NSString *)serviceName;
- (NSString *)protocolName;
- (unsigned short int)portNumber;

@end

// This is not an exhaustive list, but more than most people will ever use
extern NSString * const ONServiceEntryIPProtocolName;
extern NSString * const ONServiceEntryICMPProtocolName;
extern NSString * const ONServiceEntryTCPProtocolName;
extern NSString * const ONServiceEntryUDPProtocolName;

// Exceptions which may be raised by this class
extern NSString * const ONServiceNotFoundExceptionName;
