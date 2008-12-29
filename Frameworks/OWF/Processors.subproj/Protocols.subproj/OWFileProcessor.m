// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
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
- (void)_fetchDirectory:(OFDirectory *)directory;
- (void)_fetchRegularFile:(NSString *)filePath;
- (BOOL)_redirectToFTP;
- (BOOL)_redirectHFSPathToPosixPath;
@end

@implementation OWFileProcessor

static OFPreference *directoryIndexFilenamePreference = nil;
static OFPreference *fileRefreshIntervalPreference = nil;

+ (void)didLoad;
{
    [self registerProcessorClass:self fromContentType:[OWURL contentTypeForScheme:@"file"] toContentType:[OWContentType wildcardContentType] cost:1.0 producingSource:YES];
    directoryIndexFilenamePreference = [OFPreference preferenceForKey:@"OWDirectoryIndexFilename"];
    fileRefreshIntervalPreference = [OFPreference preferenceForKey:@"OWFileRefreshInterval"];
}

+ (OFMultiValueDictionary *)headersForFilename:(NSString *)filename;
{
    OFMultiValueDictionary *otherHeaders = [[OFMultiValueDictionary alloc] init];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = [fileManager fileAttributesAtPath:filename traverseLink:YES];
    
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
    unsigned int taskIndex = [tasks count];
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
    if ([[filePath pathExtension] hasSuffix:@"loc"] && [self _processLocationFromPath:filePath])
        return;

    OFFile *file = [OFUnixFile fileWithPath:filePath];

    NSDate *lastChanged;
    NS_DURING {
	lastChanged = [file lastChanged];
    } NS_HANDLER {
        if ([self _redirectToFTP] || [self _redirectHFSPathToPosixPath])
            return;
	[localException raise];
     lastChanged = nil; // Unreached, making the compiler happy
    } NS_ENDHANDLER;

    [self cacheDate:lastChanged forAddress:sourceAddress];

    if (![file isDirectory]) {
	[self _fetchRegularFile:filePath];
    } else if ([filePath hasSuffix:@"/"]) {
	[self _fetchDirectory:[OFUnixDirectory directoryWithFile:file]];
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
    filePath = [filePath stringByExpandingTildeInPath];

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
        NSLog(@"-[%@ %s]: %@: ignoring resources after encountering exception %@", OBShortObjectDescription(self), _cmd, filePath, [localException reason]);
#endif
        return NO;
    } NS_ENDHANDLER;

    if (address == nil)
        return NO;

    [pipeline addRedirectionContent:address sameURI:NO];

    return YES;
}

- (void)_fetchDirectory:(OFDirectory *)directory;
{
    OWObjectStream *objectStream;
    NSArray *files;
    OWContent *newContent;
    unsigned int fileIndex, fileCount;

    [self setStatusString:NSLocalizedStringFromTableInBundle(@"Reading directory", @"OWF", [OWFileProcessor bundle], @"fileprocessor status")];

    NSString *directoryIndexFilename = [directoryIndexFilenamePreference stringValue];
    if (![NSString isEmptyString:directoryIndexFilename] && [directory containsFileNamed:directoryIndexFilename]) {
	[self _fetchRegularFile:[[directory path] stringByAppendingPathComponent:directoryIndexFilename]];
	return;
    }

    objectStream = [[OWObjectStream alloc] init];
    newContent = [[OWContent alloc] initWithName:@"DirectoryListing" content:objectStream]; // TODO: Localize.
    [newContent setContentTypeString:@"ObjectStream/OWFileInfoList"];
    [newContent markEndOfHeaders];
    [pipeline cacheControl:[OWCacheControlSettings cacheSettingsWithMaxAgeInterval:[fileRefreshIntervalPreference floatValue]]];
    [pipeline addContent:newContent fromProcessor:self flags:OWProcessorContentNoDiskCache|OWProcessorTypeRetrieval];
    [newContent release];
    files = [directory sortedFiles];
    fileCount = [files count];
    for (fileIndex = 0; fileIndex < fileCount; fileIndex++) {
        OFFile *file;
        OWFileInfo *fileInfo;

        file = [files objectAtIndex:fileIndex];
        fileInfo = [[OWFileInfo alloc] initWithAddress:[OWAddress addressWithFilename:[file path]] size:[file size] isDirectory:[file isDirectory] isShortcut:[file isShortcut] lastChangeDate:[[file lastChanged] dateWithCalendarFormat:NSLocalizedStringFromTableInBundle(@"%d-%b-%Y %H:%M:%S %z", @"OWF", [OWFileProcessor bundle], @"fileprocessor lastChangeDate calendar format") timeZone:nil]];
        [objectStream writeObject:fileInfo];
        [fileInfo release];
    }
    [objectStream dataEnd];
    [objectStream release];
}

- (void)_fetchRegularFile:(NSString *)filePath;
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
