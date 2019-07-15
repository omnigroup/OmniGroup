// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

// Helper to walk the contents tree returned from OFXFileItemRecordContents and perform actions.

typedef BOOL (^OFXFileSnapshotContentsAction)(NSURL *actionURL, NSDictionary *contents, NSError **actionError);


@interface OFXFileSnapshotContentsActions : NSObject

- (BOOL)applyToContents:(NSDictionary *)contents localContentsURL:(NSURL *)localContentsURL error:(NSError **)outError;

- (id)objectForKeyedSubscript:(id)key;
- (void)setObject:(id)obj forKeyedSubscript:(id <NSCopying>)key;

@end
