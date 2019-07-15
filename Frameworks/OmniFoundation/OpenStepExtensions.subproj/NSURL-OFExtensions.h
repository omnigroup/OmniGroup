// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSURL.h>

#import <OmniFoundation/NSString-OFURLEncoding.h>

NS_ASSUME_NONNULL_BEGIN

@class NSFileManager;

// A utility function which returns the range of the path portion of an RFC1808-style URL.
extern NSRange OFURLRangeOfPath(NSString *rfc1808URL);
extern NSRange OFURLRangeOfHost(NSString *rfc1808URL);

// Appends a slash to the path of the given URL if it doesn't already end in one.
extern NSURL *OFURLWithTrailingSlash(NSURL *baseURL);

// -[NSURL isEqual:] ignores the http://tools.ietf.org/html/rfc3986#section-2.1 which says that percent-encoded octets should be compared case-insentively (%5b should be the same as %5B).
extern BOOL OFURLEqualsURL(NSURL *URL1, NSURL *URL2);

extern BOOL OFURLEqualToURLIgnoringTrailingSlash(NSURL *URL1, NSURL *URL2);

extern NSString *OFStandardizedPathForFileURL(NSURL *url, BOOL followFinalSymlink);
extern BOOL OFURLContainsURL(NSURL *containerURL, NSURL *url);
extern NSString *OFFileURLRelativePath(NSURL *baseURL, NSURL *fileURL);

extern BOOL OFGetBoolResourceValue(NSURL *url, NSString *key, BOOL *outValue, NSError **outError);

extern BOOL OFURLIsStandardizedOrMissing(NSURL *url);
extern BOOL OFURLIsStandardized(NSURL *url);


/* Roughly equivalent to -stringByAppendingPathComponent. The last path component of baseURL is never removed; a slash is inserted if necessary to separate it from the newly inserted path segment. quotedFileName must be a fully URL-escaped path component. */
extern NSURL * _Nullable OFURLRelativeToDirectoryURL( NSURL * _Nullable baseURL, NSString *quotedFileName);

/* Roughly equivalent to -stringByDeletingLastPathComponent, but without rewriting any of that portion of the path (since some WebDAV servers get upset by that). */
extern NSURL *OFDirectoryURLForURL(NSURL *url);

/* Similar to OFURLRelativeToDirectoryURL(), but nonquotedFileName must *not* be %-escaped. */
static inline NSURL *OFFileURLRelativeToDirectoryURL( NSURL * _Nullable baseURL, NSString *nonquotedFileName)
{
    NSString *quotedFileName = [NSString encodeURLString:nonquotedFileName asQuery:NO leaveSlashes:NO leaveColons:NO];
    return OFURLRelativeToDirectoryURL(baseURL, quotedFileName);
}

/* Modifies the last path segment of the given URL by appending a suffix string to it (the suffix must already contain any necessary %-escapes). If addSlash=YES, the returned URL will end in a slash; if removeSlash=YES, the returned URL will not end in a slash; otherwise its trailing slash (or lack of same) is left alone. */
extern NSURL * _Nullable OFURLWithNameAffix(NSURL *baseURL, NSString *quotedSuffix, BOOL addSlash, BOOL removeSlash);

/* Finds the range of the last path component of a URL. Returns NO if it can't find it for some reason. The returned range will not include the trailing slash, if it existed in the source URL; the length of any trailing slash is returned in *andTrailingSlash. */
extern BOOL OFURLRangeOfLastPathComponent(NSString *urlString, NSRange *lastComponentRange, unsigned *andTrailingSlash);

extern NSString *OFURLAnalogousRewrite(NSURL *oldSourceURL, NSString *oldDestination, NSURL *newSourceURL);

extern BOOL OFShouldIgnoreURLDuringScan(NSURL *fileURL);

// Scanning

// Use the same logic for finding documents inside a directory between OmniFileExchange and OmniDocumentStore
typedef BOOL (^OFScanDirectoryFilter)(NSURL *fileURL);
typedef BOOL (^OFScanPathExtensionIsPackage)(NSString *pathExtension);
typedef void (^OFScanDirectoryItemHandler)(NSFileManager *fileManager, NSURL *fileURL);
typedef BOOL (^OFScanErrorHandler)(NSURL *fileURL, NSError *error); // Return YES to continue scan, NO to stop.
extern void OFScanDirectory(NSURL *directoryURL, BOOL shouldRecurse,
                            _Nullable OFScanDirectoryFilter filterBlock,
                            OFScanPathExtensionIsPackage pathExtensionIsPackage,
                            OFScanDirectoryItemHandler itemHandler,
                            OFScanErrorHandler errorHandler);
extern void OFScanDirectoryAllowMainQueue(NSURL *directoryURL, BOOL shouldRecurse,
                                          _Nullable OFScanDirectoryFilter filterBlock,
                                          OFScanPathExtensionIsPackage pathExtensionIsPackage,
                                          OFScanDirectoryItemHandler itemHandler,
                                          OFScanErrorHandler errorHandler);

// Returns a new block that will report the given extensions as packages and use OFUTI functions to determine the others (caching them). The block returned should be used for only a short period (like a call to OFScanDirectory) since the set of known package extensions may change based on what other clients know about (in OmniFileExchange, anyway).
extern OFScanPathExtensionIsPackage OFIsPackageWithKnownPackageExtensions(NSSet * _Nullable packageExtensions);

NS_ASSUME_NONNULL_END
