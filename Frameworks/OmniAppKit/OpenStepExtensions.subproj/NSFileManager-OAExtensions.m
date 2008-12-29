// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSFileManager-OAExtensions.h"

#import <Carbon/Carbon.h> // For the Finder apple event codes
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/NSWorkspace.h>

#import "NSImage-OAExtensions.h"

RCS_ID("$Id$")

@implementation NSFileManager (OAExtensions)

- (void)setIconImage:(NSImage *)newImage forPath:(NSString *)path;
{
    [[NSWorkspace sharedWorkspace] setIcon:newImage forFile:path options:0];
}

static BOOL fillAEDescFromPath(AEDesc *fileRefDesc, NSString *path)
{
    FSRef fileRef;
    OSErr err;

    bzero(&fileRef, sizeof(fileRef));
    err = FSPathMakeRef((UInt8 *)[path fileSystemRepresentation], &fileRef, NULL);
    if (err == fnfErr || err == dirNFErr || err == notAFileErr) {
        return NO;
    } else if (err != noErr) {
        [NSException raise:NSInvalidArgumentException format:@"Unable to convert path to an FSRef (%d): %@", err, path];
    }

    AEInitializeDesc(fileRefDesc);
    err = AECoercePtr(typeFSRef, &fileRef, sizeof(fileRef), typeAlias, fileRefDesc);
    if (err != noErr) {
        [NSException raise:NSInternalInconsistencyException format:@"Unable to coerce FSRef to Alias: %d", err];
    }
    
    return YES;
}

static BOOL fillAEDescFromURL(AEDesc *fileRefDesc, NSURL *url)
{
    /* See http://developer.apple.com/technotes/tn/tn2022.html */
    /* As of 10.5, at least, Finder has started accepting these */
    
    CFDataRef urlBytes = CFURLCreateData(kCFAllocatorDefault, (CFURLRef)url, kCFStringEncodingUTF8, true);
    if (urlBytes == NULL) {
        [NSException raise:NSInternalInconsistencyException format:@"Unable to extract bytes of URL (%@)", url];
    }
    
    OSErr err;
    
    err = AECreateDesc(typeFileURL, CFDataGetBytePtr(urlBytes), CFDataGetLength(urlBytes), fileRefDesc);
    CFRelease(urlBytes);
    
    if (err != noErr) {
        [NSException raise:NSGenericException format:@"Unable to create AEDesc in fillAEDescFromURL()"];
        return NO;
    } else
        return YES;
}

/* function doSetFileComment():

 Does the actual work of consing up an AppleEvent to set a file comment. If an error occurs, it raises an exception. It does not request a response from the finder, or even check whether the event was successfully received.
 
 For details see:
 
 http://developer.apple.com/technotes/tn/tn2045.html
 http://developer.apple.com/samplecode/Sample_Code/Interapplication_Comm/MoreAppleEvents.htm

*/

static OSType finderSignatureBytes = 'MACS';

- (void)setComment:(NSString *)newComment forPath:(NSString *)path;
{
    NSAppleEventDescriptor *commentTextDesc;
    OSErr err;
    AEDesc fileDesc, builtEvent, replyEvent;
    const char *eventFormat =
        "'----': 'obj '{ "         // Direct object is the file comment we want to modify
        "  form: enum(prop), "     //  ... the comment is an object's property...
        "  seld: type(comt), "     //  ... selected by the 'comt' 4CC ...
        "  want: type(prop), "     //  ... which we want to interpret as a property (not as e.g. text).
        "  from: 'obj '{ "         // It's the property of an object...
        "      form: enum(indx), "
        "      want: type(file), " //  ... of type 'file' ...
        "      seld: @,"           //  ... selected by an alias ...
        "      from: null() "      //  ... according to the receiving application.
        "              }"
        "             }, "
        "data: @";                 // The data is what we want to set the direct object to.

    commentTextDesc = [NSAppleEventDescriptor descriptorWithString:newComment];

    /* This may raise, so do it first */
    if (!fillAEDescFromPath(&fileDesc, path))
        return;  // fillAEDescFromPath() returns without raising if the file doesn't exist

    AEInitializeDesc(&builtEvent);
    AEInitializeDesc(&replyEvent);
    err = AEBuildAppleEvent(kAECoreSuite, kAESetData,
                            typeApplSignature, &finderSignatureBytes, sizeof(finderSignatureBytes),
                            kAutoGenerateReturnID, kAnyTransactionID,
                            &builtEvent, NULL,
                            eventFormat,
                            &fileDesc, [commentTextDesc aeDesc]);

    AEDisposeDesc(&fileDesc);

    if (err != noErr) {
        [NSException raise:NSInternalInconsistencyException format:@"Unable to create AppleEvent: AEBuildAppleEvent() returns %d", err];
    }
    
    err = AESendMessage(&builtEvent, &replyEvent,
                        kAENoReply, kAEDefaultTimeout);

    AEDisposeDesc(&builtEvent);
    AEDisposeDesc(&replyEvent);

    if (err != noErr) {
        NSLog(@"Unable to set comment for file %@ (AESendMessage() returns %d)", path, err);
    }
}

- (void)updateForFileAtPath:(NSString *)path;
{
    AEDesc fileDesc, builtEvent, replyEvent;
    OSErr err;
    const char *eventFormat =
        "'----': 'obj '{ "         // Direct object is the file we want to sync
        "      form: enum(indx), "
        "      want: type(file), " //  ... of type 'file' ...
        "      seld: @,"           //  ... selected by an alias ...
        "      from: null() "      //  ... according to the receiving application.
        "}";

    /* This may raise, so do it first */
    if (!fillAEDescFromPath(&fileDesc, path))
        return;  // fillAEDescFromPath() returns without raising if the file doesn't exist

    AEInitializeDesc(&builtEvent);
    AEInitializeDesc(&replyEvent);
    err = AEBuildAppleEvent(kAEFinderSuite, kAESync,
                            typeApplSignature, &finderSignatureBytes, sizeof(finderSignatureBytes),
                            kAutoGenerateReturnID, kAnyTransactionID,
                            &builtEvent, NULL,
                            eventFormat,
                            &fileDesc);

    AEDisposeDesc(&fileDesc);

    if (err != noErr) {
        [NSException raise:NSInternalInconsistencyException format:@"Unable to create AppleEvent: AEBuildAppleEvent() returns %d", err];
    }

    err = AESendMessage(&builtEvent, &replyEvent,
                        kAENoReply, kAEDefaultTimeout);

    AEDisposeDesc(&builtEvent);
    AEDisposeDesc(&replyEvent);

    if (err != noErr) {
        NSLog(@"AESend() --> %d", err);
    }
}

/*" Messages the Finder to move the specified file to the Trash (or delete it, if the volume it's on doesn't support trash). "*/
- (BOOL)deleteFileUsingFinder:(NSString *)path;
{
    const char *eventFormat = "'----': @"; // Direct object is the file we want to delete
    
    if (!path)
        return YES;
    
    NSURL *url = [NSURL fileURLWithPath:path];
    if (!url)
        return NO;
    
    AEDesc fileDesc, builtEvent, replyEvent;
    OSErr err;

    if (!fillAEDescFromURL(&fileDesc, url))
        return NO;
    
    AEInitializeDesc(&builtEvent);
    AEInitializeDesc(&replyEvent);
    err = AEBuildAppleEvent(kAECoreSuite, kAEDelete,
                            typeApplSignature, &finderSignatureBytes, sizeof(finderSignatureBytes),
                            kAutoGenerateReturnID, kAnyTransactionID,
                            &builtEvent, NULL,
                            eventFormat,
                            &fileDesc);
    
    AEDisposeDesc(&fileDesc);
    
    if (err != noErr) {
        [NSException raise:NSInternalInconsistencyException format:@"Unable to create AppleEvent: AEBuildAppleEvent() returns %d", err];
    }
    
    err = AESendMessage(&builtEvent, &replyEvent,
                        kAEWaitReply|kAECanInteract|kAECanSwitchLayer,
                        kAEDefaultTimeout);
    
    AEDisposeDesc(&builtEvent);
    AEDisposeDesc(&replyEvent);
    
    if (err != noErr) {
        NSLog(@"AESend() --> %d", err);
        return NO;
    } else {
        return YES;
    }
}

/*" Returns any entries in the given directory which conform to any of the UTIs specified in /someUTIs/. Returns nil on error. If /errOut/ is NULL, this routine will continue past errors inspecting individual files and will return any files which can be inspected. Otherwise, it will return nil upon encountering the first error. If /fullPath/ is YES, the returned paths will have /path/ prepended to them. "*/
- (NSArray *)directoryContentsAtPath:(NSString *)path ofTypes:(NSArray *)someUTIs deep:(BOOL)recurse fullPath:(BOOL)fullPath error:(NSError **)errOut;
{
    NSObject <NSFastEnumeration> *enumerable;
    NSMutableArray *filteredChildren;
    
    if (!recurse) {
        NSArray *children = [self contentsOfDirectoryAtPath:path error:errOut];
        if (!children)
            return nil;
        
        NSUInteger entries = [children count];
        if (entries == 0)
            return children;
    
        filteredChildren = [NSMutableArray arrayWithCapacity:entries];
        enumerable = children;
    } else {
        NSDirectoryEnumerator *children = [self enumeratorAtPath:path];
        if (!children)
            return nil;
        
        filteredChildren = [NSMutableArray array];
        enumerable = children;
    }
    
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    
    for(NSString *childName in enumerable) {
        NSString *childPath = [path stringByAppendingPathComponent:childName];
        NSString *childType = [ws typeOfFile:childPath error:errOut];
        if (!childType) {
            if (errOut)
                return nil;
            else
                continue;
        }
        for(NSString *someDesiredType in someUTIs) {
            if ([ws type:childType conformsToType:someDesiredType]) {
                [filteredChildren addObject:fullPath ? childPath : childName];
                break;
            }
        }
    }
    
    return filteredChildren;
}

@end
