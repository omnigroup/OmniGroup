// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniFileStore/OFSDocumentStoreScope.h>
#import <OmniFileStore/OFSDocumentStore.h>

RCS_ID("$Id$");

#if OFS_DOCUMENT_STORE_SUPPORTED

@implementation OFSDocumentStoreScope

+ (OFSDocumentStoreScope *)defaultUbiquitousScope;
{
    // Hidden preference to totally disable iCloud support until Apple fixes some edge case bugs.
    if ([OFSDocumentStoreDisableUbiquityPreference boolValue])
        return nil; // return a local documents directory?
    
    static NSString *fullContainerID = nil;
    static OFSDocumentStoreScope *defaultScope = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // We don't use the bundle identifier since we want iPad and Mac apps to be able to share a container!
        NSString *cloudID = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIApplicationCloudID"];
        NSString *containerID = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIApplicationCloudContainerID"];
        
        OBASSERT(!((cloudID == nil) ^ (containerID == nil)));
        
        // A nil container ID just means to use whatever the default cloud container is in our entitlements
        if (cloudID) {
            fullContainerID = [[NSString alloc] initWithFormat:@"%@.%@", cloudID, containerID];
        }

        defaultScope = [[OFSDocumentStoreScope alloc] initUbiquitousScopeWithContainerID:fullContainerID];
    });
    
    return defaultScope;
}

- (id)initUbiquitousScopeWithContainerID:(NSString *)aContainerID;
{
    OBPRECONDITION(aContainerID);
    
    if (!(self = [super init]))
        return nil;
    
    _containerID = [aContainerID copy];
    
    return self;
}

- (id)initLocalScopeWithURL:(NSURL *)aURL;
{
    OBPRECONDITION(aURL);
    
    if (!(self = [super init]))
        return nil;
    
    _url = [aURL copy];
    
    return self;
}

- (void)dealloc;
{
    [_containerID release];
    
    [super dealloc];
}

- (NSURL *)containerURL;
{
    if (_containerID == nil)
        return nil;

    // We don't cache this since if the app is backgrounded and then brought back to the foreground, iCloud may have been turned off/on while we were in the background.
    return [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier:_containerID];
}

- (NSURL *)documentsURL:(NSError **)outError;
{
    if (_url)
        return _url;
    
    NSURL *containerURL = [self containerURL];
    if (!containerURL) {
        // Most likely iCloud is not enabled for the app or the user hasn't registered an account.
        OBUserCancelledError(outError);
        return nil;
    }
    
    NSURL *documentsURL = [containerURL URLByAppendingPathComponent:@"Documents"];
    NSString *documentsPath = [[documentsURL absoluteURL] path];
    BOOL directory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:documentsPath isDirectory:&directory]) {
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:documentsPath withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"Error creating ubiquitous documents directory \"%@\": %@", documentsPath, [error toPropertyList]);
            if (outError)
                *outError = error;
            return nil;
        }
    } else {
        OBASSERT(directory); // remove it if it is a file?
    }
    
    return documentsURL;
}

static NSString *_standardizedPathForURL(NSURL *url)
{
    OBASSERT([url isFileURL]);
    NSString *urlPath = [[url absoluteURL] path];
    
    NSString *path = [[urlPath stringByResolvingSymlinksInPath] stringByStandardizingPath];
    
    // In some cases this doesn't normalize /private/var/mobile and /var/mobile to the same thing.
    path = [path stringByRemovingPrefix:@"/var/mobile/"];
    path = [path stringByRemovingPrefix:@"/private/var/mobile/"];
    
    return path;
}

static BOOL _urlContainedByURL(NSURL *url, NSURL *containerURL)
{
    if (!containerURL)
        return NO;
    
    // -[NSFileManager contentsOfDirectoryAtURL:...], when given something in file://localhost/var/mobile/... will return file URLs with non-standarized paths like file://localhost/private/var/mobile/...  Terrible.
    OBASSERT([containerURL isFileURL]);
    
    NSString *urlPath = _standardizedPathForURL(url);
    NSString *containerPath = _standardizedPathForURL(containerURL);
    
    if (![containerPath hasSuffix:@"/"])
        containerPath = [containerPath stringByAppendingString:@"/"];
    
    return [urlPath hasPrefix:containerPath];
}

- (BOOL)isFileInContainer:(NSURL *)fileURL;
{
    return _urlContainedByURL(fileURL, [self documentsURL:NULL]);
}

- (BOOL)isUbiquitous;
{
    return _containerID != nil;
}

@synthesize containerID = _containerID, url = _url;

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    NSMutableString *desc = [NSMutableString stringWithFormat:@"<%@:%p", NSStringFromClass([self class]), self];
    if (_containerID)
        [desc appendFormat:@" container=\"%@\"", _containerID];
    if (_url)
        [desc appendFormat:@" url=\"%@\"", _url];
    [desc appendString:@">"];
    return desc;
}

@end

#endif // OFS_DOCUMENT_STORE_SUPPORTED
