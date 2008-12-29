// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/FileManagement.subproj/OFFile.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@class NSCalendarDate, NSNumber, NSLock;
@class OFDirectory;

extern NSLock *fileOpsLock;

@interface OFFile : OFObject
{
    OFDirectory *directory;
    NSString *name;
    NSString *path;
}

+ fileWithDirectory:(OFDirectory *)aDirectory name:(NSString *)aName;
+ fileWithPath:(NSString *)aPath;

- initWithDirectory:(OFDirectory *)aDirectory name:(NSString *)aName;
- initWithPath:(NSString *)aPath;

- (NSString *)name;
- (NSString *)path;

- (BOOL)isDirectory;
- (BOOL)isShortcut;
- (NSNumber *)size;
- (NSCalendarDate *)lastChanged;

@end

@interface OFMutableFile : OFFile
{
    struct {
        unsigned int isDirectory:1;
        unsigned int isShortcut:1;
    } flags;
    NSNumber *size;
    NSCalendarDate *lastChanged;
}

- (void)setIsDirectory:(BOOL)shouldBeDirectory;
- (void)setIsShortcut:(BOOL)shouldBeShortcut;
- (void)setSize:(NSNumber *)aSize;
- (void)setLastChanged:(NSCalendarDate *)aDate;
- (void)setPath:(NSString *)aPath;

@end
