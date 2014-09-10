// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXContentIdentifier.h"

#import "OFXFileSnapshotRemoteEncoding.h"
#import "OFXFileSnapshot-Internal.h"

RCS_ID("$Id$")


static NSMutableDictionary *ContentDisplayNameByHash;

static void _OFXSerializeContentDisplayNameAction(void (^action)(void))
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t actionQueue;
    dispatch_once(&onceToken, ^{
        actionQueue = dispatch_queue_create("com.omnigroup.OmniFileExchange.ContentDisplayName", DISPATCH_QUEUE_SERIAL);
    });
    
    dispatch_sync(actionQueue, action);
}

// Should be called w/in a file coordinator if needed. These identifiers are just for logging purposes.
NSString *OFXContentIdentifierForURL(NSURL *fileURL, NSError **outError)
{
    NSMutableDictionary *contents = [NSMutableDictionary new];
    if (!OFXFileItemRecordContents(OFXInfoContentsType, contents, fileURL, outError))
        return nil;
    
    return OFXContentIdentifierForContents(contents);
}

NSString *OFXContentIdentifierForContents(NSDictionary *contents)
{
    if (!contents)
        return nil;
    
    __autoreleasing NSError *error;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:contents format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!plistData) {
        [error log:@"Error computing content data for %@", contents];
        return nil;
    }
    
    NSString *hash = OFXHashFileNameForData(plistData);
    
    return hash;
}


void OFXRegisterDisplayNameForContentAtURL(NSURL *fileURL, NSString *displayName)
{
    _OFXSerializeContentDisplayNameAction(^{
        if (!ContentDisplayNameByHash)
            ContentDisplayNameByHash = [NSMutableDictionary new];
        
        NSString *hash = OFXContentIdentifierForURL(fileURL, NULL);
        OBASSERT(ContentDisplayNameByHash[hash] == nil);
        NSLog(@"Registering %@ -> %@", hash, displayName);
        ContentDisplayNameByHash[hash] = displayName;
    });
}

NSString *OFXLookupDisplayNameForContentIdentifier(NSString *contentIdentifier)
{
    __block NSString *result;
    _OFXSerializeContentDisplayNameAction(^{
        result = [ContentDisplayNameByHash[contentIdentifier] copy];
    });
    return result;
}

void _OFXNoteContentChanged(id self, const char *file, unsigned line, NSURL *fileURL)
{
    DEBUG_CONTENT(1, @"%@ now has content \"%@\" at %@:%d", fileURL, OFXLookupDisplayNameForContentIdentifier(OFXContentIdentifierForURL(fileURL, NULL)), [[NSString stringWithUTF8String:file] lastPathComponent], line);
}
void _OFXNoteContentDeleted(id self, const char *file, unsigned line, NSURL *fileURL)
{
    DEBUG_CONTENT(1, @"%@ deleted at %@:%d", fileURL, [[NSString stringWithUTF8String:file] lastPathComponent], line);
}
void _OFXNoteContentMoved(id self, const char *file, unsigned line, NSURL *sourceURL, NSURL *destURL)
{
    DEBUG_CONTENT(1, @"%@ moved to %@ with content \"%@\" at %@:%d", sourceURL, destURL, OFXLookupDisplayNameForContentIdentifier(OFXContentIdentifierForURL(destURL, NULL)), [[NSString stringWithUTF8String:file] lastPathComponent], line);
}

