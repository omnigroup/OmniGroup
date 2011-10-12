// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentStoreGroupItem.h"

#import <OmniFoundation/OFPreference.h>

#import "OUIDocumentStoreItem-Internal.h"
#import "OUIDocumentStoreFileItem-Internal.h"

RCS_ID("$Id$");

NSString * const OUIDocumentStoreGroupItemFileItemsBinding = @"fileItems";

@implementation OUIDocumentStoreGroupItem
{
    NSString *_name;
    NSSet *_fileItems;
}

- (void)dealloc;
{
    [_name release];
    [_fileItems release];
    [super dealloc];
}

@synthesize fileItems = _fileItems;
- (void)setFileItems:(NSSet *)fileItems;
{
    if (OFISEQUAL(_fileItems, fileItems))
        return;
    
    [_fileItems release];
    _fileItems = [fileItems copy];
    
    OBFinishPortingLater("Recompute our derived date and fix up KVO for file item dates");
    OBFinishPortingLater("Observe the our file items and update ourselves if a document is renamed"); // actually, we can't do this in all cases, so maybe we should just require movers to call us to inform us about the change
}

#pragma mark -
#pragma mark OUIDocumentStoreItem protocol

@synthesize name = _name;

- (NSDate *)date;
{
    NSDate *date = nil;
    
    for (OUIDocumentStoreFileItem *fileItem in _fileItems) {
        NSDate *itemDate = fileItem.date;
        if (!date || [date compare:itemDate] == NSOrderedAscending)
            date = itemDate;
    }
    
    return date;
}

// OBFinishPorting: Add KVO observances for our fileItems and derive these from our file items
- (BOOL)isReady;
{
    return NO;
}

- (BOOL)hasUnresolvedConflicts;
{
    return NO;
}
- (BOOL)isDownloaded;
{
    return YES;
}
- (BOOL)isDownloading;
{
    return NO;
}
- (BOOL)isUploaded;
{
    return YES;
}
- (BOOL)isUploading;
{
    return NO;
}
- (double)percentDownloaded;
{
    return 100;
}
- (double)percentUploaded;
{
    return 100;
}

@end
