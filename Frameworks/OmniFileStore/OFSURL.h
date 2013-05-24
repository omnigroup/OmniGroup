// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/NSString-OFURLEncoding.h>

#if 0
// We treat folders with extensions as packages since we can't be sure whether they are or not (since we might not have the UTI defintion if a file came from a newer app version). *But* we reserve the 'folder' extension to be for user-defined folders (as does iWork).
extern BOOL OFSIsFolder(NSURL *url);
extern NSString * const OFSDocumentStoreFolderPathExtension;
extern NSString *OFSFolderNameForFileURL(NSURL *fileURL); // Given a URL to a document, return the filename of the containing folder (including the "folder" extension) or nil if it is not in such a folder (top level, in the inbox, etc).
#endif

extern BOOL OFSShouldIgnoreURLDuringScan(NSURL *fileURL);

// Use the same logic for finding documents inside a directory between OFSSync* and OFSDocumentStore's sync support.
typedef BOOL (^OFSScanDirectoryFilter)(NSURL *fileURL);
typedef BOOL (^OFSScanPathExtensionIsPackage)(NSString *pathExtension);
typedef void (^OFSScanDirectoryItemHandler)(NSFileManager *fileManager, NSURL *fileURL);
extern void OFSScanDirectory(NSURL *directoryURL, BOOL shouldRecurse,
                             OFSScanDirectoryFilter filterBlock,
                             OFSScanPathExtensionIsPackage pathExtensionIsPackage,
                             OFSScanDirectoryItemHandler itemHandler);

// Returns a new block that will report the given extensions as packages and use OFUTI functions to determine the others (caching them). The block returned should be used for only a short period (like a call to OFSScanDirectory) since the set of known package extensions may change based on what other clients know about (in OmniFileExchange, anyway).
extern OFSScanPathExtensionIsPackage OFSIsPackageWithKnownPackageExtensions(NSSet *packageExtensions);

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// iOS uses an 'Inbox' folder in the app's ~/Documents for opening files from other applications
extern BOOL OFSInInInbox(NSURL *url);
extern BOOL OFSIsZipFileType(NSString *uti);
extern NSString * const OFSDocumentInteractionInboxFolderName;
#endif
extern OFSScanDirectoryFilter OFSScanDirectoryExcludeInboxItemsFilter(void);

extern BOOL OFSGetBoolResourceValue(NSURL *url, NSString *key, BOOL *outValue, NSError **outError);

extern BOOL OFSURLIsStandardizedOrMissing(NSURL *url);
extern BOOL OFSURLIsStandardized(NSURL *url);


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

/* Modifies the last path segment of the given URL by appending a suffix string to it (the suffix must already contain any necessary %-escapes). If addSlash=YES, the returned URL will end in a slash; if removeSlash=YES, the returned URL will not end in a slash; otherwise its trailing slash (or lack of same) is left alone. */
extern NSURL *OFSURLWithNameAffix(NSURL *baseURL, NSString *quotedSuffix, BOOL addSlash, BOOL removeSlash);

/* Finds the range of the last path component of a URL. Returns NO if it can't find it for some reason. The returned range will not include the trailing slash, if it existed in the source URL; the length of any trailing slash is returned in *andTrailingSlash. */
extern BOOL OFSURLRangeOfLastPathComponent(NSString *urlString, NSRange *lastComponentRange, unsigned *andTrailingSlash);

extern NSString *OFSURLAnalogousRewrite(NSURL *oldSourceURL, NSString *oldDestination, NSURL *newSourceURL);

