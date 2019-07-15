// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class OFXAccountClientParameters;
@class ODAVConnection, ODAVFileInfo;

@interface OFXAccountInfo : NSObject

- initWithLocalAccountDirectory:(NSURL *)localAccountDirectoryURL remoteAccountURL:(NSURL *)remoteAccountURL temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL clientParameters:(OFXAccountClientParameters *)clientParameters error:(NSError **)outError;

@property(nonatomic,readonly) NSURL *remoteAccountURL;

- (BOOL)updateWithConnection:(ODAVConnection *)connection accountFileInfo:(ODAVFileInfo *)accountFileInfo clientFileInfos:(NSArray <ODAVFileInfo *> *)clientFileInfos remoteTemporaryDirectoryFileInfo:(ODAVFileInfo *)remoteTemporaryDirectoryFileInfo serverDate:(NSDate *)serverDate error:(NSError **)outError;

@property(nonatomic,readonly) NSString *groupIdentifier;

@end

OB_HIDDEN extern NSString * const OFXInfoFileName;
OB_HIDDEN extern NSString * const OFXClientPathExtension;

OB_HIDDEN extern NSString * const OFXAccountInfo_Group;
