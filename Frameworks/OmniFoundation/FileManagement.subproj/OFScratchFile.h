// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

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
