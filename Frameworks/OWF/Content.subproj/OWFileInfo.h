// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Content.subproj/OWFileInfo.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@class NSDate, NSNumber;
@class OWAddress;

#import <OWF/OWContentCacheProtocols.h>

@interface OWFileInfo : OFObject <OWConcreteCacheEntry>
{
    OWAddress *address;
    NSNumber *size;
    struct {
        unsigned int fileTypeKnown:1;  // if 0, then isDirectory and isShortcut are meaningless
        unsigned int isDirectory:1;
        unsigned int isShortcut:1;
        
        unsigned int fixed:1;  // for debugging purposes
    } flags;
    NSDate *lastChangeDate;
    NSString *cachedTitle;
    NSString *cachedName;
}

+ (OWContentType *)contentType;

- initWithAddress:(OWAddress *)anAddress size:(NSNumber *)aSize isDirectory:(BOOL)isDirectory isShortcut:(BOOL)isShortcut lastChangeDate:(NSDate *)aDate;

- initWithLastChangeDate:(NSDate *)aDate;

// Normally, "name" is derived from the address, but we can override that here
- (void)setName:(NSString *)fileName;
- (void)setTitle:(NSString *)documentTitle;

// Attributes

- (OWAddress *)address;
- (NSNumber *)size;
- (BOOL)isDirectory;
- (BOOL)isShortcut;
- (NSDate *)lastChangeDate;
- (NSString *)title;

// Derived attributes

- (NSString *)name;
// - (NSString *)addressString;

@end
