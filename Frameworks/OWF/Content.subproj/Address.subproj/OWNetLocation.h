// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Content.subproj/Address.subproj/OWNetLocation.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@interface OWNetLocation : OFObject
{
    NSString *username;
    NSString *password;
    NSString *hostname;
    NSString *port;

    NSString *shortDisplayName;
}

+ (OWNetLocation *)netLocationWithString:(NSString *)aNetLocation;
- initWithUsername:(NSString *)aUsername password:(NSString *)aPassword hostname:(NSString *)aHostname port:(NSString *)aPort;

- (NSString *)username;
- (NSString *)password;
- (NSString *)hostname;
- (NSString *)port;

- (NSString *)hostnameWithPort;
- (NSString *)displayString;
- (NSString *)shortDisplayString;

@end
