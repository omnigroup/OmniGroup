// Copyright 2008-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/NSString-OFURLEncoding.h>

@class NSURL;

@interface OFSFileInfo : OFObject
{
@private
    NSURL *_originalURL;
    NSString *_name;
    BOOL _exists;
    BOOL _directory;
    off_t _size;
    NSDate *_lastModifiedDate;
}

+ (NSString *)nameForURL:(NSURL *)url;
+ (NSString *)UTIForFilename:(NSString *)name;
+ (NSString *)UTIForURL:(NSURL *)url;
+ (void)registerNativeUTI:(NSString *)UTI forFileExtension:(NSString *)fileExtension;

- initWithOriginalURL:(NSURL *)url name:(NSString *)name exists:(BOOL)exists directory:(BOOL)directory size:(off_t)size lastModifiedDate:(NSDate *)date;

// Accessors
- (NSURL *)originalURL;
- (NSString *)name;
- (BOOL)exists;
- (BOOL)isDirectory;
- (off_t)size;
- (NSDate *)lastModifiedDate;

// Filename manipulation
- (BOOL)hasExtension:(NSString *)extension;
- (NSString *)UTI;

// Other stuff
- (NSComparisonResult)compareByURLPath:(OFSFileInfo *)otherInfo;
- (NSComparisonResult)compareByName:(OFSFileInfo *)otherInfo;

@end

/* Roughly equivalent to -stringByAppendingPathComponent. The last path component of baseURL is never removed; a slash is inserted if necessary to separate it from the newly inserted path segment. quotedFileName must be a fully URL-escaped path component. */
extern NSURL *OFSURLRelativeToDirectoryURL(NSURL *baseURL, NSString *quotedFileName);

/* Roughly equivalent to -stringByDeletingLastPathComponent, but without rewriting any of that portion of the path (since some WebDAV servers get upset by that). */
extern NSURL *OFSDirectoryURLForURL(NSURL *url);

/* Similar to OFSURLRelativeToDirectoryURL(), but nonquotedFileName must *not* be %-escaped. */
static inline NSURL *OFSFileURLRelativeToDirectoryURL(NSURL *baseURL, NSString *nonquotedFileName)
{
    NSString *quotedFileName = [NSString encodeURLString:nonquotedFileName asQuery:NO leaveSlashes:NO leaveColons:NO];
    return OFSURLRelativeToDirectoryURL(baseURL, quotedFileName);
}

/* A utility function which returns the range of the path portion of an RFC1808-style URL. */
extern NSRange OFSURLRangeOfPath(NSString *rfc1808URL);

/* Appends a slash to the path of the given URL if it doesn't already end in one. */
extern NSURL *OFSURLWithTrailingSlash(NSURL *baseURL);

/* Modifies the last path segment of the given URL by appending a suffix string to it (the suffix must already contain any necessary %-escapes). If addSlash=YES, the returned URL will end in a slash; if removeSlash=YES, the returned URL will not end in a slash; otherwise its trailing slash (or lack of same) is left alone. */
extern NSURL *OFSURLWithNameAffix(NSURL *baseURL, NSString *quotedSuffix, BOOL addSlash, BOOL removeSlash);

/* Finds the range of the last path component of a URL. Returns NO if it can't find it for some reason. The returned range will not include the trailing slash, if it existed in the source URL; the length of any trailing slash is returned in *andTrailingSlash. */
extern BOOL OFSURLRangeOfLastPathComponent(NSString *urlString, NSRange *lastComponentRange, unsigned *andTrailingSlash);

extern NSString *OFSURLAnalogousRewrite(NSURL *oldSourceURL, NSString *oldDestination, NSURL *newSourceURL);

