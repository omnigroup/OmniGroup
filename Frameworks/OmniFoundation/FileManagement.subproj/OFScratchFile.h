// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/FileManagement.subproj/OFScratchFile.h 93428 2007-10-25 16:36:11Z kc $

#import <OmniFoundation/OFObject.h>

@class NSData, NSMutableArray;
@class OFDataCursor;

@interface OFScratchFile : OFObject
{
    NSString                   *filename;
    NSData                     *contentData;
    NSString                   *contentString;
    NSMutableArray             *retainedObjects;
}

+ (OFScratchFile *)scratchFileNamed:(NSString *)aName error:(NSError **)outError;
+ (OFScratchFile *)scratchDirectoryNamed:(NSString *)aName error:(NSError **)outError;

- initWithFilename:(NSString *)aFilename;
- (NSString *)filename;
- (NSData *)contentData;
- (NSString *)contentString;
- (OFDataCursor *)contentDataCursor;

- (void)retainObject:anObject;

@end
