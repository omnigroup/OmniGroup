// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDocumentStore/ODSUtilities.h>

RCS_ID("$Id$")

#import <MobileCoreServices/MobileCoreServices.h>

NSString * const ODSDocumentInteractionInboxFolderName = @"Inbox";

BOOL ODSInInInbox(NSURL *url)
{
    // Check to see if the URL directly points to the Inbox.
    NSString *lastPathComponent = [url lastPathComponent];
    if (lastPathComponent != nil && ([lastPathComponent caseInsensitiveCompare:ODSDocumentInteractionInboxFolderName] == NSOrderedSame)) {
        return YES;
    }
    
    // URL does not directly point to Inbox, check if it points to a file directly in the Inbox.
    NSURL *pathURL = [url URLByDeletingLastPathComponent]; // Remove the filename.
    NSString *lastPathComponentString = [pathURL lastPathComponent];
    
    BOOL isInInbox = (lastPathComponentString != nil && [lastPathComponentString caseInsensitiveCompare:ODSDocumentInteractionInboxFolderName] == NSOrderedSame);
    return isInInbox;
}

BOOL ODSIsZipFileType(NSString *uti)
{
    // Check both of the semi-documented system UTIs for zip (in case one goes away or something else weird happens).
    // Also check for a temporary hack UTI we had, in case the local LaunchServices database hasn't recovered.
    return UTTypeConformsTo((__bridge CFStringRef)uti, CFSTR("com.pkware.zip-archive")) ||
    UTTypeConformsTo((__bridge CFStringRef)uti, CFSTR("public.zip-archive")) ||
    UTTypeConformsTo((__bridge CFStringRef)uti, CFSTR("com.omnigroup.zip"));
}

OFScanDirectoryFilter ODSScanDirectoryExcludeInboxItemsFilter(void)
{
    return [^BOOL(NSURL *fileURL){
        // We never want to acknowledge files in the inbox directly. Instead they'll be dealt with when they're handed to us via document interaction and moved.
        return ODSInInInbox(fileURL) == NO;
    } copy];
};

