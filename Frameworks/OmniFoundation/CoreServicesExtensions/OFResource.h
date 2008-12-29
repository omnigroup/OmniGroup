// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/CoreServicesExtensions/OFResource.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@class OFResourceFork;

#import <CoreServices/CoreServices.h> // For Handle

@interface OFResource : OFObject
{
    OFResourceFork *resourceFork;
    Handle resourceHandle;
    
    short resourceID;
    NSString *type;
    NSString *name;
}

- (id)initInResourceFork:(OFResourceFork *)resFork withHandle:(Handle)resHandle;

// API

- (void)recacheInfo;
- (void)saveInfoToDisk;

- (Handle)resourceHandle;
- (void)setResourceHandle:(Handle)newHandle;

- (NSString *)name;
- (void)setName:(NSString *)newName;
- (short)resourceID;
- (void)setResourceID:(short)newResourceID;
- (NSString *)type;

- (unsigned long)size;

@end
