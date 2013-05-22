// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileMetadata-Internal.h"

RCS_ID("$Id$")

@implementation OFXFileMetadata

#pragma mark - Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    if (_editIdentifier)
        dict[@"editIdentifier"] = _editIdentifier;
    dict[@"fileURL"] = _fileURL;
    dict[@"fileSize"] = @(_fileSize);
    dict[@"directory"] = @(_directory);
    dict[@"creationDate"] = _creationDate;
    dict[@"modificationDate"] = _modificationDate;
    dict[@"hasDownloadQueued"] = @(_hasDownloadQueued);
    dict[@"downloaded"] = @(self.downloaded);
    dict[@"downloading"] = @(_downloading);
    dict[@"percentDownloaded"] = @(_percentDownloaded);
    dict[@"uploaded"] = @(self.uploaded);
    dict[@"uploading"] = @(_uploading);
    dict[@"percentUploaded"] = @(_percentUploaded);
    dict[@"deleting"] = @(_deleting);

    return dict;
}

@end
