// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshotContentsActions.h"

#import "OFXFileSnapshot-Internal.h"

RCS_ID("$Id$")

@implementation OFXFileSnapshotContentsActions
{
    NSMutableDictionary *_actionByFileType;
}

- init;
{
    if (!(self = [super init]))
        return nil;
    
    _actionByFileType = [[NSMutableDictionary alloc] init];
    
    return self;
}

- (id)objectForKeyedSubscript:(id)key;
{
    return _actionByFileType[key];
}

- (void)setObject:(id)obj forKeyedSubscript:(id <NSCopying>)key;
{
    _actionByFileType[key] = [obj copy]; // value is an action block
}

- (BOOL)applyToContents:(NSDictionary *)contents localContentsURL:(NSURL *)localContentsURL error:(NSError **)outError;
{
    NSString *fileType = contents[kOFXContents_FileTypeKey];
    
    // TODO: Add a default action? As written, we'll just silently skip over unknown file types.
    OFXFileSnapshotContentsAction action = self[fileType];
    if (action) {
        if (!action(localContentsURL, contents, outError)) {
            OBChainError(outError);
            return NO;
        }
    }
    
    if ([fileType isEqualToString:kOFXContents_FileTypeDirectory]) {
        NSDictionary *children = contents[kOFXContents_DirectoryChildrenKey];
        
        // -enumerateKeysAndObjectsUsingBlock: adds an autorelease pool. Add our own strong error pointer to hang onto it for the caller.
        __block NSError *error = nil;
        __block BOOL success = YES;
        [children enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *child, BOOL *stop) {
            __autoreleasing NSError *childError;
            if (![self applyToContents:child localContentsURL:[localContentsURL URLByAppendingPathComponent:name] error:&childError]) {
                success = NO;
                error = childError;
                *stop = YES;
            }
        }];
        
        if (!success && outError)
            *outError = error;
        return success;
    }
    
    return YES;
}

@end

