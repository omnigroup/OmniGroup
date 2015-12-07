// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSEncryptingFileManager.h>

#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CoreFoundation/CoreFoundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/OFSDocumentKey.h>
#import <OmniFileStore/OFSSegmentedEncryption.h>
#import <OmniFileStore/Errors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <dispatch/dispatch.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

@implementation OFSEncryptingFileManager
{
    OFSFileManager <OFSConcreteFileManager> *underlying;
    OFSDocumentKey *keyManager;
}

- initWithBaseURL:(NSURL *)baseURL delegate:(id <OFSFileManagerDelegate>)delegate error:(NSError **)outError NS_UNAVAILABLE;
{
    /* We could implement this, but we don't want to use it: we want to combine the multiple PROPFINDs of the encrypted info, which means the URL parsing has to happen at a layer above us. */
    OBRejectInvalidCall(self, _cmd, @"This method should not be called directly");
}

- initWithFileManager:(OFSFileManager <OFSConcreteFileManager> *)underlyingFileManager keyStore:(OFSDocumentKey *)keyStore error:(NSError **)outError;
{
    if (!(self = [super initWithBaseURL:[underlyingFileManager baseURL] delegate:[underlyingFileManager delegate] error:outError]))
        return nil;
    
    underlying = underlyingFileManager;
    keyManager = keyStore;
    
    return self;
}

- (void)invalidate
{
    [underlying invalidate];
    underlying = nil;
    keyManager = nil;
    [super invalidate];
}

@synthesize keyStore = keyManager;

#pragma mark OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;
{
    OBRejectInvalidCall(self, _cmd, @"No URL scheme for this OFS class");
}

/* NOTE: The file info we return has an inaccurate 'size' field (because we return the size of the underlying file, which has a magic number, file keys, IVs, and checksums prepended).  The only place that ODAVFileInfo.size is used right now is producing progress bars, so that isn't really a problem. */

- (ODAVFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;
{
    return [underlying fileInfoAtURL:url error:outError];
}

/* TODO: Filename masking */

- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;
{
    return [underlying directoryContentsAtURL:url havingExtension:extension error:outError];
}

- (NSMutableArray *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections error:(NSError **)outError;
{
    return [underlying directoryContentsAtURL:url collectingRedirects:redirections error:outError];
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
{
    NSData *encrypted = [underlying dataWithContentsOfURL:url error:outError];
    if (!encrypted)
        return nil;

    return [OFSSegmentEncryptWorker decryptData:encrypted withKey:keyManager error:outError];
}

- (NSURL *)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;
{
    NSData *encrypted = [OFSSegmentEncryptWorker encryptData:data withKey:keyManager error:outError];
    if (!encrypted)
        return nil;
    
    return [underlying writeData:encrypted toURL:url atomically:atomically error:outError];
}

- (NSURL *)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;
{
    return [underlying createDirectoryAtURL:url attributes:attributes error:outError];
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;
{
    return [underlying moveURL:sourceURL toURL:destURL error:outError];
}

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;
{
    return [underlying deleteURL:url error:outError];
}

@end

