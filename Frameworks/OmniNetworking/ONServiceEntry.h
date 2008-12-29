// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniNetworking/ONServiceEntry.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniBase/OBObject.h>

#import "FrameworkDefines.h"

@interface ONServiceEntry : OBObject
{
    NSString *serviceName;
    NSString *protocolName;
    int portNumber;
}

+ (ONServiceEntry *)httpService;
+ (ONServiceEntry *)smtpService;

+ serviceEntryNamed:(NSString *)aServiceName protocolName:(NSString *)aProtocolName;

+ (void)hintPort:(int)portNumber forServiceNamed:(NSString *)aServiceName protocolName:(NSString *)aProtocolName;

- (NSString *)serviceName;
- (NSString *)protocolName;
- (unsigned short int)portNumber;

@end

// This is not an exhaustive list, but more than most people will ever use
OmniNetworking_EXTERN NSString *ONServiceEntryIPProtocolName;
OmniNetworking_EXTERN NSString *ONServiceEntryICMPProtocolName;
OmniNetworking_EXTERN NSString *ONServiceEntryTCPProtocolName;
OmniNetworking_EXTERN NSString *ONServiceEntryUDPProtocolName;

// Exceptions which may be raised by this class
OmniNetworking_EXTERN NSString *ONServiceNotFoundExceptionName;
