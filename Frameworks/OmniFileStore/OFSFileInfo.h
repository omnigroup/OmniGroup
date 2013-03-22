// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSURL;

@interface OFSFileInfo : NSObject <NSCopying>
{
@private
    NSURL *_originalURL;
    NSString *_name;
    BOOL _exists;
    BOOL _directory;
    off_t _size;
    NSDate *_lastModifiedDate;
    NSString *_ETag;
}

+ (NSString *)nameForURL:(NSURL *)url;
- initWithOriginalURL:(NSURL *)url name:(NSString *)name exists:(BOOL)exists directory:(BOOL)directory size:(off_t)size lastModifiedDate:(NSDate *)date ETag:(NSString *)ETag;
- initWithOriginalURL:(NSURL *)url name:(NSString *)name exists:(BOOL)exists directory:(BOOL)directory size:(off_t)size lastModifiedDate:(NSDate *)date;

// Accessors
@property(nonatomic,readonly) NSURL *originalURL;
@property(nonatomic,readonly) NSString *name;
@property(nonatomic,readonly) BOOL exists;
@property(nonatomic,readonly) BOOL isDirectory;
@property(nonatomic,readonly) off_t size;
@property(nonatomic,readonly) NSDate *lastModifiedDate;
@property(nonatomic,readonly) NSString *ETag; // Only set for files returned from WebDAV

// Filename manipulation
- (BOOL)hasExtension:(NSString *)extension;
- (NSString *)UTI;

// Other stuff
- (NSComparisonResult)compareByURLPath:(OFSFileInfo *)otherInfo;
- (NSComparisonResult)compareByName:(OFSFileInfo *)otherInfo;

// Returns YES only if the two share an ETag, modification date and the modification date is strictly before the server date (since ETags include info from the server date). This is still pretty hokey, but it is better than just comparing the ETag or server date. Really it would be nicer if each resource had a 64-bit incrementing version counter.
- (BOOL)isSameAsFileInfo:(OFSFileInfo *)otherInfo asOfServerDate:(NSDate *)serverDate;

@end
