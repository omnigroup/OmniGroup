// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWFileProcessor.h>

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWAddress.h>
#import <OWF/OWCacheControlSettings.h>
#import <OWF/OWContent.h>
#import <OWF/OWContentInfo.h>
#import <OWF/OWContentType.h>
#import <OWF/OWFileDataStream.h>
#import <OWF/OWFileInfo.h>
#import <OWF/OWObjectStream.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

@interface OWFileProcessor (Private)
- (void)_processDirectoryAtPath:(NSString *)filePath;
- (void)_fetchDirectoryWithPath:(NSString *)directoryPath;
- (void)_fetchRegularFileWithPath:(NSString *)filePath;
- (BOOL)_redirectToFTP;
- (BOOL)_redirectHFSPathToPosixPath;
@end

@implementation OWFileProcessor

static OFPreference *directoryIndexFilenamePreference = nil;
static OFPreference *fileRefreshIntervalPreference = nil;

+ (void)didLoad;
{
    [self registerProcessorClass:self fromContentType:[OWURL contentTypeForScheme:@"file"] toContentType:[OWContentType wildcardContentType] cost:1.0f producingSource:YES];
    directoryIndexFilenamePreference = [OFPreference preferenceForKey:@"OWDirectoryIndexFilename"];
    fileRefreshIntervalPreference = [OFPreference preferenceForKey:@"OWFileRefreshInterval"];
}

+ (OFMultiValueDictionary *)headersForFilename:(NSString *)filename;
{
    OFMultiValueDictionary *otherHeaders = [[OFMultiValueDictionary alloc] init];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:filename error:NULL];
    
    // File size
    NSNumber *fileSize = [attributes objectForKey:NSFileSize];
    if (fileSize != nil)
        [otherHeaders addObject:[fileSize stringValue] forKey:@"Content-Length"];
        
    // Last modified
    NSDate *lastModified = [attributes objectForKey:NSFileModificationDate];
    if (lastModified != nil) {
        NSCalendarDate *calendarDate = [NSCalendarDate dateWithTimeIntervalSinceReferenceDate:[lastModified timeIntervalSinceReferenceDate]];
        [otherHeaders addObject:[calendarDate descriptionWithCalendarFormat:@"%a, %d %b %Y %H:%M:%S"] forKey:@"Last-Modified"];
    }
        
    return otherHeaders;
}

- (void)process;
{
    // Fix for <bug://bugs/20833>: Security: Arbitrary file disclosure vulnerability in AppleWebKit  [CERT VU#998369, XMLHttpRequest]
    // Don't allow access to local files from remote resources

    OWAddress *restrictedRemoteResourceAddress = nil;
    OWAddress *referringAddress = [self.pipeline contextObjectForKey:OWCacheArcReferringAddressKey];

    NSArray *tasks = [self.pipeline tasks];
    NSUInteger taskIndex = [tasks count];
    while (taskIndex-- > 0) {
        OWTask *task = [tasks objectAtIndex:taskIndex];
        OWContentInfo *contentInfo = [task parentContentInfo];
        if ([contentInfo isHeader]) continue;
        OWAddress *contentInfoAddress = [contentInfo address];
        if (contentInfoAddress && ![[[contentInfoAddress url] scheme] isEqualToString:@"file"]) {
            restrictedRemoteResourceAddress = contentInfoAddress;
        }
    }
    if (referringAddress && ![[[referringAddress url] scheme] isEqualToString:@"file"]) {
        restrictedRemoteResourceAddress = referringAddress;
    }

    if (restrictedRemoteResourceAddress != nil && ![sourceAddress isWhitelisted]) {
        [NSException raise:@"OWFileProcessor" format:NSLocalizedStringFromTableInBundle(@"<%@> is not allowed to access <%@>", @"OWF", [OWFileProcessor bundle], @"OWFileProcessor error: file access denied"), [restrictedRemoteResourceAddress addressString], [sourceAddress addressString]];
    }
    [self setStatusString:NSLocalizedStringFromTableInBundle(@"Opening file", @"OWF", [OWFileProcessor bundle], @"fileprocessor status")];

    NSString *filePath = [sourceAddress localFilename];
    NSString *resolvedPath = [[[NSFileManager defaultManager] resolveAliasesInPath:filePath] stringByStandardizingPath];
    if (resolvedPath != nil && ![resolvedPath isEqualToString:[filePath stringByStandardizingPath]]) { // redirect if our file is a Mac alias
        // NSLog(@"filePath: %@, resolvedPath: %@", filePath, resolvedPath);
        [self.pipeline addRedirectionContent:[OWAddress addressWithFilename:resolvedPath] sameURI:NO];
        return;
    }

    // -attributesOfItemAtPath:error: will return nil if there is a ~ in this.
    filePath = [filePath stringByExpandingTildeInPath];
    
    NSError *error = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
    if (!attributes) {
        if ([self _redirectToFTP] || [self _redirectHFSPathToPosixPath])
            return;
        // Used to raise here since this was in an exception handler. See:
        // DiffSVN -r 106193:HEAD $SVNROOT/trunk/OmniGroup/Frameworks/OWF/Processors.subproj/Protocols.subproj/OWFileProcessor.m
        OBRequestConcreteImplementation(self, _cmd);
    }

    [self cacheDate:[attributes fileModificationDate] forAddress:sourceAddress];

    if (![[attributes fileType] isEqualToString:NSFileTypeDirectory]) {
	[self _fetchRegularFileWithPath:filePath];
    } else if ([filePath hasSuffix:@"/"]) {
	[self _fetchDirectoryWithPath:filePath];
    } else {
        [self _processDirectoryAtPath:filePath];
    }
}

@end

@implementation OWFileProcessor (Private)

- (void)_processDirectoryAtPath:(NSString *)filePath;
{
#warning Document wrappers (including RTFD) are not supported at present

    // Redirect from file:/.../x to file:/.../x/
    [self.pipeline addRedirectionContent:[OWAddress addressWithFilename:[filePath stringByAppendingString:@"/"]] sameURI:YES];
}

- (void)_fetchDirectoryWithPath:(NSString *)directoryPath;
{
    [self setStatusString:NSLocalizedStringFromTableInBundle(@"Reading directory", @"OWF", [OWFileProcessor bundle], @"fileprocessor status")];

    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *filenames = [fileManager contentsOfDirectoryAtPath:directoryPath error:&error];
    if (filenames == nil) {
        // TODO: Handle error for real.
        return;
    }
    
    NSString *directoryIndexFilename = [directoryIndexFilenamePreference stringValue];
    if (![NSString isEmptyString:directoryIndexFilename] && [filenames containsObject:directoryIndexFilename]) {
	[self _fetchRegularFileWithPath:[directoryPath stringByAppendingPathComponent:directoryIndexFilename]];
	return;
    }

    OWObjectStream *objectStream = [[OWObjectStream alloc] init];
    OWContent *newContent = [[OWContent alloc] initWithName:@"DirectoryListing" content:objectStream]; // TODO: Localize.
    [newContent setContentTypeString:@"ObjectStream/OWFileInfoList"];
    [newContent markEndOfHeaders];
    [self.pipeline cacheControl:[OWCacheControlSettings cacheSettingsWithMaxAgeInterval:[fileRefreshIntervalPreference floatValue]]];
    [self.pipeline addContent:newContent fromProcessor:self flags:OWProcessorContentNoDiskCache|OWProcessorTypeRetrieval];
    
    NSArray *sortedFilenames = [filenames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *filename in sortedFilenames) {
        NSString *path = [directoryPath stringByAppendingPathComponent:filename];
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:NULL];
        NSString *fileType = [attributes objectForKey:NSFileType];
        OWFileInfo *fileInfo = [[OWFileInfo alloc] initWithAddress:[OWAddress addressWithFilename:path] size:[attributes objectForKey:NSFileSize] isDirectory:fileType == NSFileTypeDirectory isShortcut:fileType == NSFileTypeSymbolicLink lastChangeDate:[attributes objectForKey:NSFileModificationDate]];
        [objectStream writeObject:fileInfo];
    }
    [objectStream dataEnd];
}

- (void)_fetchRegularFileWithPath:(NSString *)filePath;
{
    [self setStatusString:NSLocalizedStringFromTableInBundle(@"Reading file", @"OWF", [OWFileProcessor bundle], @"fileprocessor status")];

    OWDataStream *fileStream = [[OWFileDataStream alloc] initWithContentsOfFile:filePath];
    if (fileStream == nil)
        [NSException raise:@"OWFileProcessor" format:NSLocalizedStringFromTableInBundle(@"Unable to read file data from <%@>", @"OWF", [OWFileProcessor bundle], @"OWFileProcessor error: file unreadable"), [sourceAddress addressString]];

    OWContent *newContent = [[OWContent alloc] initWithName:@"File" content:fileStream];
    [newContent addHeader:OWContentIsSourceMetadataKey value:[NSNumber numberWithBool:YES]];
    OWContentType *newContentType = [[sourceAddress contextDictionary] objectForKey:OWAddressContentTypeContextKey];
    if (newContentType != nil)
        [newContent addHeader:OWContentTypeHeaderString value:newContentType];
    else
        [newContent addHeaders:[OWContentType contentTypeAndEncodingForFilename:filePath isLocalFile:YES]];
    [newContent addHeaders:[[self class] headersForFilename:filePath]];
    [newContent markEndOfHeaders];
    [self.pipeline cacheControl:[OWCacheControlSettings cacheSettingsWithMaxAgeInterval:[fileRefreshIntervalPreference floatValue]]];
    [self.pipeline addContent:newContent fromProcessor:self flags:OWProcessorContentIsSource|OWProcessorContentNoDiskCache|OWProcessorTypeRetrieval];

    [self setStatusString:NSLocalizedStringFromTableInBundle(@"Finished reading", @"OWF", OMNI_BUNDLE, @"fileprocessor status")];
}

- (BOOL)_redirectToFTP;
{
    OWURL *url = [sourceAddress url];
    NSString *netLocation = [url netLocation];
    if (netLocation == nil || [netLocation length] == 0 || [netLocation isEqualToString:@"localhost"])
	return NO;

    OWURL *ftpURL = [OWURL urlWithScheme:@"ftp" netLocation:netLocation path:[url path] params:[url params] query:[url query] fragment:[url fragment]];
    
    [self.pipeline addRedirectionContent:[OWAddress addressWithURL:ftpURL] sameURI:YES];
    return YES;
}

#if SUPPORT_HFS_PATHS
// <bug:///89060> (Stop using deprecated API in OWFileProcessor)

- (NSString *)_pathForVolumeNamed:(NSString *)name;
{
    unsigned int volumeIndex = 1;
    HFSUniStr255 volumeName;
    FSRef volumeFSRef;
    while (FSGetVolumeInfo(kFSInvalidVolumeRefNum, volumeIndex++, NULL, kFSVolInfoNone, NULL, &volumeName, &volumeFSRef) == noErr) {
        if ([[NSString stringWithCharacters:volumeName.unicode length:volumeName.length] isEqualToString:name]) {
            NSURL *url = CFBridgingRelease(CFURLCreateFromFSRef(NULL, &volumeFSRef));
            return [url path];
        }
    }
    return nil;
}

- (BOOL)_redirectHFSPathToPosixPath;
{
    NSMutableArray *pathComponents = [[[[sourceAddress url] path] componentsSeparatedByString:@"/"] mutableCopy];
    NSString *volumeName = [pathComponents objectAtIndex:0];
    NSString *volumePath = [self _pathForVolumeNamed:volumeName];
#ifdef DEBUG_HFS_PATHS
    NSLog(@"volumeName = %@, volumePath = %@", volumeName, volumePath);
#endif
    if (volumePath == nil)
        return NO;
    if ([volumePath hasSuffix:@"/"])
        volumePath = [volumePath substringToIndex:[volumePath length] - 1];
    [pathComponents replaceObjectAtIndex:0 withObject:volumePath];
    NSString *posixPath = [pathComponents componentsJoinedByString:@"/"];
#ifdef DEBUG_HFS_PATHS
    NSLog(@"posixPath = %@", posixPath);
#endif
    [self.pipeline addRedirectionContent:[OWAddress addressWithFilename:posixPath] sameURI:YES];
    return YES;
}
#else

- (BOOL)_redirectHFSPathToPosixPath;
{
    return NO;
}

#endif

@end
