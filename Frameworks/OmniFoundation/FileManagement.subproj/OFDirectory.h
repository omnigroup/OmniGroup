// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/FileManagement.subproj/OFDirectory.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>

@class NSArray;
@class NSMutableArray;
@class OFFile;

@interface OFDirectory : OFObject
{
    NSString *path;
    NSArray *sortedFiles;
}

+ directoryWithPath:(NSString *)aDirectoryPath;
+ directoryWithFile:(OFFile *)aFile;
- initWithPath:(NSString *)aDirectoryPath;
- initWithFile:(OFFile *)aFile;
- (NSString *)path;
- (NSArray *)files;
- (NSArray *)sortedFiles;
- (BOOL)containsFileNamed:(NSString *)aName;

@end

@interface OFMutableDirectory : OFDirectory
{
    NSMutableArray *files;
}

- (void)setPath:(NSString *)aPath;
- (void)setFiles:(NSMutableArray *)someFiles;
- (void)addFile:(OFFile *)aFile;

@end
