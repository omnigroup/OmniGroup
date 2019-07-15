// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSData;

@interface OFScratchFile : OFObject

+ (OFScratchFile *)scratchFileNamed:(NSString *)aName error:(NSError **)outError;
+ (OFScratchFile *)scratchDirectoryNamed:(NSString *)aName error:(NSError **)outError;

- initWithFileURL:(NSURL *)fileURL;

@property(nonatomic,readonly) NSURL *fileURL;

- (NSData *)contentData;
- (NSString *)contentString;

@end
