// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXPersistentPropertyList.h"

RCS_ID("$Id$")

/*
 Probably need a better name for this. The approach with this is to persist simple values if possible, but if not to just reset.
 */

@implementation OFXPersistentPropertyList
{
    NSURL *_fileURL;
    NSMutableDictionary *_plist;
}

- initWithFileURL:(NSURL *)fileURL;
{
    OBPRECONDITION([fileURL isFileURL]);
    
    if (!(self = [super init]))
        return nil;
    
    _fileURL = fileURL;
    
    __autoreleasing NSError *dataError;
    NSData *plistData = [[NSData alloc] initWithContentsOfURL:fileURL options:0 error:&dataError];
    if (!plistData) {
        if (![dataError causedByMissingFile])
            [dataError log:@"Error reading property list at %@", fileURL];
        _plist = [[NSMutableDictionary alloc] init];
    } else {
        __autoreleasing NSError *plistError;
        id plist = [NSPropertyListSerialization propertyListWithData:plistData options:0 format:NULL error:&plistError];
        if (!plist)
            [plistError log:@"Error deserializing property list at %@", fileURL];
        if (![plist isKindOfClass:[NSDictionary class]]) {
            NSLog(@"Property list at %@ is not a dictionary but a %@: %@", fileURL, [plist class], plist);
            plist = nil;
        }
        _plist = [[NSMutableDictionary alloc] initWithDictionary:plist];
    }
    
    return self;
}

- (id)objectForKeyedSubscript:(id)key;
{
    return _plist[key];
}

- (void)setObject:(id)obj forKeyedSubscript:(id <NSCopying>)key;
{
    _plist[key] = [obj copy];
    
    // We don't coalesce writes at all currently, expecting updates to be infrequent.
    
    __autoreleasing NSError *plistError;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:_plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&plistError];
    if (!plistData) {
        [plistError log:@"Error serializing property list for %@", _fileURL];
        OBASSERT_NOT_REACHED("Should not put non-plist values in here");
        return;
    }
    
    __autoreleasing NSError *writeError;
    if (![plistData writeToURL:_fileURL options:NSDataWritingAtomic error:&writeError]) {
        [writeError log:@"Error writing property list to %@", _fileURL];
    }
}

@end
