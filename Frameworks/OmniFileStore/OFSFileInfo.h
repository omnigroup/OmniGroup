// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSURL;

@interface OFSFileInfo : OFObject
{
@private
    NSURL *_originalURL;
    NSString *_name;
    BOOL _exists;
    BOOL _directory;
    off_t _size;
}

+ (NSString *)nameForURL:(NSURL *)url;

- initWithOriginalURL:(NSURL *)url name:(NSString *)name exists:(BOOL)exists directory:(BOOL)directory size:(off_t)size;

- (NSURL *)originalURL;
- (NSString *)name;
- (BOOL)exists;
- (BOOL)isDirectory;
- (off_t)size;

- (BOOL)hasExtension:(NSString *)extension;

- (NSComparisonResult)compareByURLPath:(OFSFileInfo *)otherInfo;

@end

extern NSURL *OFSFileURLRelativeToDirectoryURL(NSURL *baseURL, NSString *fileName);
