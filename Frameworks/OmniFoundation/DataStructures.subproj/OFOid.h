// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFOid.h 104581 2008-09-06 21:18:23Z kc $

#import <Foundation/NSData.h>

#define OFOID_LENGTH (12)

// OFOid is a concrete subclass of NSData that automatically generates globally unique bytes each time an instance is generated.  This is a subclass of NSData to allow for efficient use with EOF.
@interface OFOid : NSData
{
@public
    unsigned char bytes[OFOID_LENGTH];
}

+ (OFOid *)oid;
+ (OFOid *)oidWithData:(NSData *)data;
+ (OFOid *)oidWithBytes:(const void *)newBytes length:(NSUInteger)length;
+ (OFOid *)oidWithString:(NSString *)aString;
+ (OFOid *)zeroOid;

- initWithBytes:(const void *)bytes length:(NSUInteger)length;
- initWithString:(NSString *)string;
- (const void *)bytes;
- (unsigned int)length;

- (NSString *)sqlString;
- (BOOL)isZero;

- (NSString *)description;
    // Returns a '0x' prefixed hex string appropriate for entry into SQL

@end

// EOF2.2 has a bug in that custom value primary keys are sent -intValue even if they aren't subclasses of NSNumber.  EOF is just using this to see if the key is null (and interpreting zero NSNumbers as null).  We just return 1 from this method and assume that the return value is never used.
@interface OFOid (EOF2_2_BugFix)
- (int)intValue;
@end
