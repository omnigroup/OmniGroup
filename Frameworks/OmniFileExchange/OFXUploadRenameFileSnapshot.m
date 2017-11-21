// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXUploadRenameFileSnapshot.h"

#import "OFXFileSnapshot-Internal.h"
#import "OFXFileState.h"

RCS_ID("$Id$")

@implementation OFXUploadRenameFileSnapshot

// We are a local temporary copy of the snapshot that is being renamed. Update ourselves as if the rename has happened here. Also, bump our version number.
- (BOOL)prepareToUploadRename:(NSError **)outError;
{
    OBPRECONDITION(self.localState.missing, "Otherwise use the normal upload transfer and snapshot");
    OBPRECONDITION(self.localState.userMoved, "Why are we uploading, otherwise");

    // Write out updated info dictionary as if the move has happened already.
    NSMutableDictionary *infoDictionary = [self.infoDictionary mutableCopy];
    infoDictionary[kOFXInfo_PathKey] = self.versionDictionary[kOFXVersion_RelativePath];
    
    if (![self _updateInfoDictionary:infoDictionary error:outError])
        return NO;

    NSMutableDictionary *versionDictionary = [self.versionDictionary mutableCopy];
    
    NSNumber *oldVersion = versionDictionary[kOFXVersion_NumberKey];
    OBASSERT_NOTNULL(oldVersion);
    versionDictionary[kOFXVersion_NumberKey] = @([oldVersion unsignedLongValue] + 1);
    
    return [self _updateVersionDictionary:versionDictionary reason:@"init upload rename" error:outError];
}

@end
