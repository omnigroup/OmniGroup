// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshotUploadTransfer.h"

#import <OmniDAV/ODAVConnection.h>
#import "OFXFileSnapshot.h"

RCS_ID("$Id$")

@implementation OFXFileSnapshotUploadTransfer

- (id)initWithConnection:(ODAVConnection *)connection currentSnapshot:(OFXFileSnapshot *)currentSnapshot remoteTemporaryDirectory:(NSURL *)remoteTemporaryDirectory;
{
    OBPRECONDITION(currentSnapshot, "Should always have a starting snapshot, but it might be locally created on the first upload");
    OBPRECONDITION(remoteTemporaryDirectory);
    OBPRECONDITION([[remoteTemporaryDirectory lastPathComponent] isEqual:@"tmp"], "should be the tmp directory, not a the full container/account");
    
    if (!(self = [super initWithConnection:connection]))
        return nil;
    
    _currentSnapshot = currentSnapshot;
    _remoteTemporaryDirectoryURL = [[connection suggestRedirectedURLForURL:remoteTemporaryDirectory] copy];
    
    // Upload into a temporary location, doing server side copies for unchanged files.
    // TODO: Add code to clean up entries in the tmp directory that have been abandoned for long enough. Doing this w/o being suseptible to clock skew will require a non-naive approach.
    NSString *uploadID = [NSString stringWithFormat:@"upload-%@", OFXMLCreateID()];
    _temporaryRemoteSnapshotURL = [_remoteTemporaryDirectoryURL URLByAppendingPathComponent:uploadID isDirectory:YES];
    DEBUG_TRANSFER(2, @"  Temporary upload location %@", _temporaryRemoteSnapshotURL);
    
    return self;
}

- (OFXFileSnapshot *)uploadingSnapshot;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (void)finished:(NSError *)errorOrNil;
{
    [super finished:errorOrNil];
    TRACE_SIGNAL(OFXFileSnapshotUploadTransfer.finished);
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, [self.uploadingSnapshot shortDescription]];
}

@end
