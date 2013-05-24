// Copyright 1997-2005, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWFileProcessor.h"

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OWAddress.h"
#import "OWCacheControlSettings.h"
#import "OWContent.h"
#import "OWContentInfo.h"
#import "OWContentType.h"
#import "OWFileDataStream.h"
#import "OWFileInfo.h"
#import "OWObjectStream.h"
#import "OWPipeline.h"
#import "OWURL.h"

RCS_ID("$Id$")

@interface OWFileProcessor (Private)
- (void)_processDirectoryAtPath:(NSString *)filePath;
- (BOOL)_processLocationFromPath:(NSString *)filePath;
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
        
    return [otherHeaders autorelease];
}

- (void)process;
{
    // Fix for <bug://bugs/20833>: Security: Arbitrary file disclosure vulnerability in AppleWebKit  [CERT VU#998369, XMLHttpRequest]
    // Don't allow access to local files from remote resources

    OWAddress *restrictedRemoteResourceAddress = nil;
    OWAddress *referringAddress = [pipeline contextObjectForKey:OWCacheArcReferringAddressKey];

    NSArray *tasks = [pipeline tasks];
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
        [pipeline addRedirectionContent:[OWAddress addressWithFilename:resolvedPath] sameURI:NO];
        return;
    }

    // -attributesOfItemAtPath:error: will return nil if there is a ~ in this.
    filePath = [filePath stringByExpandingTildeInPath];
    
    if ([[filePath pathExtension] hasSuffix:@"loc"] && [self _processLocationFromPath:filePath])
        return;

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
    [pipeline addRedirectionContent:[OWAddress addressWithFilename:[filePath stringByAppendingString:@"/"]] sameURI:YES];
}

- (BOOL)_processLocationFromPath:(NSString *)filePath;
{
    // First, verify that the data fork is really empty
    if ([[NSData dataWithContentsOfMappedFile:filePath] length] != 0)
        return NO; // Wait, this doesn't look like the .fileloc files we know!
    
    // Now, read the 'url' resource
    OWAddress *address = nil;
    NS_DURING {
        OFResourceFork *resourceFork = [[[OFResourceFork alloc] initWithContentsOfFile:filePath] autorelease];
        NSString *urlString = [NSString stringWithData:[resourceFork dataForResourceType:'url ' atIndex:0] encoding:NSMacOSRomanStringEncoding];
        address = [OWAddress addressForDirtyString:urlString];
    } NS_HANDLER {
#ifdef DEBUG
        NSLog(@"-[%@ %@]: %@: ignoring resources after encountering exception %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), filePath, [localException reason]);
#endif
        return NO;
    } NS_ENDHANDLER;

    if (address == nil)
        return NO;

    [pipeline addRedirectionContent:address sameURI:NO];

    return YES;
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
    [pipeline cacheControl:[OWCacheControlSettings cacheSettingsWithMaxAgeInterval:[fileRefreshIntervalPreference floatValue]]];
    [pipeline addContent:newContent fromProcessor:self flags:OWProcessorContentNoDiskCache|OWProcessorTypeRetrieval];
    [newContent release];
    
    NSArray *sortedFilenames = [filenames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *filename in sortedFilenames) {
        NSString *path = [directoryPath stringByAppendingPathComponent:filename];
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:NULL];
        NSString *fileType = [attributes objectForKey:NSFileType];
        OWFileInfo *fileInfo = [[OWFileInfo alloc] initWithAddress:[OWAddress addressWithFilename:path] size:[attributes objectForKey:NSFileSize] isDirectory:fileType == NSFileTypeDirectory isShortcut:fileType == NSFileTypeSymbolicLink lastChangeDate:[attributes objectForKey:NSFileModificationDate]];
        [objectStream writeObject:fileInfo];
        [fileInfo release];
    }
    [objectStream dataEnd];
    [objectStream release];
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
    [newContent addHeaders:[isa headersForFilename:filePath]];
    [newContent markEndOfHeaders];
    [pipeline cacheControl:[OWCacheControlSettings cacheSettingsWithMaxAgeInterval:[fileRefreshIntervalPreference floatValue]]];
    [pipeline addContent:newContent fromProcessor:self flags:OWProcessorContentIsSource|OWProcessorContentNoDiskCache|OWProcessorTypeRetrieval];
    [newContent release];
    [fileStream release];

    [self setStatusString:NSLocalizedStringFromTableInBundle(@"Finished reading", @"OWF", [OWFileProcessor bundle], @"fileprocessor status")];
}

- (BOOL)_redirectToFTP;
{
    OWURL *url;
    NSString *netLocation;
    OWURL *ftpURL;

    url = [sourceAddress url];
    netLocation = [url netLocation];
    if (netLocation == nil || [netLocation length] == 0 || [netLocation isEqualToString:@"localhost"])
	return NO;

    ftpURL = [OWURL urlWithScheme:@"ftp" netLocation:netLocation path:[url path] params:[url params] query:[url query] fragment:[url fragment]];
    
    [pipeline addRedirectionContent:[OWAddress addressWithURL:ftpURL] sameURI:YES];
    return YES;
}

- (NSString *)_pathForVolumeNamed:(NSString *)name;
{
    // <bug:///89060> (Stop using deprecated API in OWFileProcessor)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    unsigned int volumeIndex;
    HFSUniStr255 volumeName;
    FSRef volumeFSRef;
    
    volumeIndex = 1;
    while (FSGetVolumeInfo(kFSInvalidVolumeRefNum, volumeIndex++, NULL, kFSVolInfoNone, NULL, &volumeName, &volumeFSRef) == noErr) {
        if ([[NSString stringWithCharacters:volumeName.unicode length:volumeName.length] isEqualToString:name]) {
            NSURL *url;

            url = [(NSURL *)CFURLCreateFromFSRef(NULL, &volumeFSRef) autorelease];
            return [url path];
        }
    }
    return nil;
#pragma clang diagnostic pop
}

- (BOOL)_redirectHFSPathToPosixPath;
{
    NSMutableArray *pathComponents;
    NSString *volumeName;
    NSString *volumePath;
    NSString *posixPath;

    pathComponents = [[[[[sourceAddress url] path] componentsSeparatedByString:@"/"] mutableCopy] autorelease];
    volumeName = [pathComponents objectAtIndex:0];
    volumePath = [self _pathForVolumeNamed:volumeName];
#ifdef DEBUG_HFS_PATHS
    NSLog(@"volumeName = %@, volumePath = %@", volumeName, volumePath);
#endif
    if (volumePath == nil)
        return NO;
    if ([volumePath hasSuffix:@"/"])
        volumePath = [volumePath substringToIndex:[volumePath length] - 1];
    [pathComponents replaceObjectAtIndex:0 withObject:volumePath];
    posixPath = [pathComponents componentsJoinedByString:@"/"]; 
#ifdef DEBUG_HFS_PATHS
    NSLog(@"posixPath = %@", posixPath);
#endif
    [pipeline addRedirectionContent:[OWAddress addressWithFilename:posixPath] sameURI:YES];
    return YES;
}

@end
