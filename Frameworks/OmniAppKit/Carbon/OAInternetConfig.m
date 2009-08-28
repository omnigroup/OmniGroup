// Copyright 2000-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAInternetConfig.h"

#import <AppKit/NSPanel.h>
#import <OmniFoundation/OmniFoundation.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Carbon/Carbon.h>
#import <OmniBase/OmniBase.h>

#import "OAOSAScript.h"

RCS_ID("$Id$")

// The InternetConfig documentation can be found at http://www.quinn.echidna.id.au/Quinn/Config/.

@interface OAInternetConfig (Private)

typedef struct _OAInternetConfigInfo {
    BOOL valid;
    NSString *applicationName;
} OAInternetConfigInfo;

- (NSString *)_helperKeyNameForScheme:(NSString *)scheme;
- (void)sendMailViaEntourageTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy blindCarbonCopy:(NSString *)blindCarbonCopy subject:(NSString *)subject body:(NSString *)body;
- (void)sendMailViaAppleScriptWithApplication:(NSString *)mailApp mailtoURL:(NSString *)url codedBody:(NSString *)body;
- (NSString *)mailtoURLWithTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy blindCarbonCopy:(NSString *)blindCarbonCopy subject:(NSString *)subject;

static NSString *OANameForInternetConfigErrorCode(OSStatus errorCode);
static NSString *OAFragmentedAppleScriptStringForString(NSString *string);

@end

static NSString *helperKeyPrefix = nil;

@implementation OAInternetConfig

+ (void)initialize;
{
    OBINITIALIZE;

    helperKeyPrefix = (NSString *)CFStringCreateWithPascalString(NULL, kICHelper, kCFStringEncodingMacRoman);
}

+ (OAInternetConfig *)internetConfig;
{
    return [[[self alloc] init] autorelease];
}

+ (unsigned long)applicationSignature;
{
    NSString *bundleSignature;
    NSData *signatureBytes;

    bundleSignature = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleSignature"];
    if (!bundleSignature)
        return FOUR_CHAR_CODE('????');
    
    signatureBytes = [bundleSignature dataUsingEncoding:[NSString defaultCStringEncoding]];
    if (!signatureBytes || ([signatureBytes length] < 4))
        return FOUR_CHAR_CODE('????');
    
    return *(const OSType *)[signatureBytes bytes];
}

// Init and dealloc

- init;
{
    ICInstance anInstance;

    if ([super init] == nil)
        return nil;
    if (ICStart(&anInstance, [[self class] applicationSignature]) != noErr)
        return nil;
    internetConfigInstance = anInstance;
    return self;
}

- (void)dealloc;
{
    ICStop(internetConfigInstance);
    [super dealloc];
}

//

- (NSString *)iToolsAccountName:(NSError **)outError;
{
    NSData *iToolsAccountPreferenceValue = [self dataForPreferenceKey:@"IToolsAccountName" error:outError];
    
    if (iToolsAccountPreferenceValue == nil)
        return nil;
    
    NSString *result = (NSString *)CFStringCreateWithPascalString(NULL, [iToolsAccountPreferenceValue bytes], kCFStringEncodingMacRoman);
    return [result autorelease];
}

- (NSString *)helperApplicationForScheme:(NSString *)scheme;
{
    // Check Launch Services
    {
        OSStatus status;
        CFURLRef schemeURL, helperApplicationURL;

        schemeURL = (CFURLRef)[NSURL URLWithString:[scheme stringByAppendingString:@":"]];
        status = LSGetApplicationForURL(schemeURL, kLSRolesAll, NULL, &helperApplicationURL);
        if (status == noErr) {
            NSString *helperApplicationPath, *helperApplicationName;

            // Check to make sure the registered helper application isn't us
            helperApplicationPath = [(NSURL *)helperApplicationURL path];
            helperApplicationName = [[helperApplicationPath lastPathComponent] stringByDeletingPathExtension];
            return helperApplicationName;
        }
    }

    // Check Internet Config
    {
        NSString *helperKeyString;
        Str255 helperKeyPascalString;
        ICAppSpec helperApplication;
        ICAttr attribute;
        long helperApplicationSize;
        OSStatus error;

        helperKeyString = [self _helperKeyNameForScheme:scheme];
        CFStringGetPascalString((CFStringRef)helperKeyString, helperKeyPascalString, sizeof(helperKeyPascalString) - 1, kCFStringEncodingMacRoman);

        helperApplicationSize = sizeof(helperApplication);
        error = ICGetPref(internetConfigInstance, helperKeyPascalString, &attribute, &helperApplication, &helperApplicationSize);
        switch (error) {
            case noErr:
                return [(NSString *)CFStringCreateWithPascalString(NULL, helperApplication.name, kCFStringEncodingMacRoman) autorelease];
                break;
            case icPrefNotFoundErr:
#ifdef DEBUG
                NSLog(@"OAInternetConfig: ICGetPref found no helper application for %@", scheme);
#endif
                return nil;
            default:
                NSLog(@"OAInternetConfig: ICGetPref returned an error while getting key %@: %@", helperKeyString, OANameForInternetConfigErrorCode(error));
                return nil;
        }
    }
}

- (BOOL)setApplicationCreatorCode:(long)applicationCreatorCode name:(NSString *)applicationName forScheme:(NSString *)scheme error:(NSError **)outError;
{
    Str255 helperKeyPascalString;
    NSString *helperKeyString = [self _helperKeyNameForScheme:scheme];
    CFStringGetPascalString((CFStringRef)helperKeyString, helperKeyPascalString, sizeof(helperKeyPascalString) - 1, kCFStringEncodingMacRoman);
    
    ICAppSpec helperApplication;
    helperApplication.fCreator = applicationCreatorCode;
    CFStringGetPascalString((CFStringRef)applicationName, helperApplication.name, sizeof(helperApplication.name) - 1, kCFStringEncodingMacRoman);
    long helperApplicationSize = sizeof(helperApplication);
    
    OSStatus error = ICSetPref(internetConfigInstance, helperKeyPascalString, kICAttrNoChange, &helperApplication, helperApplicationSize);
    
    if (error == noErr)
        return YES;
    
    NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to set '%@' to be owner for url scheme '%@'.", @"OmniAppKit", OMNI_BUNDLE, @"internet config error"), applicationName, scheme];
    NSString *reason;
    
    if (error == icPermErr)
        reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"ICSetPref returned permissions when attempting setting key %@", @"OmniAppKit", [OAInternetConfig bundle], "internet config error"), helperKeyString];
    else
        reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"ICSetPref returned an error while setting key %@: %@", @"OmniAppKit", [OAInternetConfig bundle], "internet config error"), helperKeyString, OANameForInternetConfigErrorCode(error)];
    NSDictionary  *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
    if (outError)
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:error userInfo:userInfo];
    return NO;
}

- (BOOL)launchURL:(NSString *)urlString error:(NSError **)outError;
    // -launchURL: now uses Launch Services rather than Internet Config.  Since this method was really the driving force behind the class (and it's now both simpler to implement and much more robust), we should probably just torch this whole class and replace it with OALaunchServices or something.  But I'm not doing that now, because don't want to change more code than absolutely necessary this close to release.  (I wouldn't have even touched this if Internet Config hadn't been crashing on URLs which encoded Kanji characters.)
    // RDR: actually, why not kill this method entirely, since 10.1 and newer have -[NSWorkspace openURL:] which is documented to be a similar wrapper for LSOpenCFURLRef()? Maybe also pull the other stuff in this class which isn't used by our apps and is based on non-Apple-recommended API, and rename the class to something more appropriate? 
{
    CFURLRef url = CFURLCreateWithString(NULL, (CFStringRef)urlString, NULL);
    OSStatus error = LSOpenCFURLRef(url, NULL);
    
    if (url != NULL) // We get NULL for urlStrings like <help:runscript="Essentials:_scripts:PDFFileOpener.as" string="Essentials:SystemOverview:SystemOverview.pdf"> (found on the Help button in <file:///Developer/Documentation/Essentials/SystemOverview/>)
        CFRelease(url);
    
    if (error == noErr)
        return YES;
    
    NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to launch URL %@", @"OmniAppKit", [OAInternetConfig bundle], "launch services error"), urlString];
    NSString *reason = NSLocalizedStringFromTableInBundle(@"Launch Services returned an error while opening URL %@: %@", @"OmniAppKit", [OAInternetConfig bundle], "launch services error");
    NSDictionary  *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
    if (outError)
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:error userInfo:userInfo];

    return NO;
}

// Download folder

#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5  // Uses API deprecated on 10.5
- (NSString *)downloadFolderPath:(NSError **)outError;
{
    NSData *icPrefData;
    const struct ICFileSpec *downloadFolderICFileSpecPtr;
    OSStatus error;
    const char *errorFunc;
    FSRef downloadFolderFSRef;
    Boolean didSearch;
    UInt8 path[PATH_MAX + 1];

    icPrefData = [self dataForPreferenceKey:@"DownloadFolder" error:outError];
    
    if (icPrefData == nil || [icPrefData length] < kICFileSpecHeaderSize)
        return nil;

    downloadFolderICFileSpecPtr = [icPrefData bytes];

    bzero(&downloadFolderFSRef, sizeof(downloadFolderFSRef));
    error = FSpMakeFSRef(&(downloadFolderICFileSpecPtr->fss), &downloadFolderFSRef);
    errorFunc = "FSpMakeFSRef";

    if ([icPrefData length] > kICFileSpecHeaderSize) {
        const FSRef *inRef;
        const AliasRecord * const aliasPointer = &(downloadFolderICFileSpecPtr->alias);
        Size aliasSize = GetAliasSizeFromPtr(aliasPointer);

        // this must be a real handle, or FSResolveAlias returns -50

        Handle aliasHandle = NewHandle(aliasSize);
        HLock(aliasHandle);
        memcpy(*aliasHandle, aliasPointer, aliasSize);
        HUnlock(aliasHandle);

        // Resolve the alias record.
        
        if (error == noErr) {
            // We have an FSRef available to us, so pass it to ResolveAlias
            inRef = &downloadFolderFSRef;
        } else {
            inRef = NULL;
        }

        error = FSResolveAlias(inRef, (AliasHandle)aliasHandle, &downloadFolderFSRef, &didSearch);
        
        DisposeHandle(aliasHandle);
        errorFunc = "FSResolveAlias";
    }
    
    if (error != noErr) {
        NSLog(@"-[OAInternetConfig downloadFolderPath]: Error resolving download path: %s() failed: %@", errorFunc, OANameForInternetConfigErrorCode(error));
        return nil;
    }
    
    error = FSRefMakePath(&downloadFolderFSRef, path, sizeof(path));
    if (error != noErr) {
        NSLog(@"-[OAInternetConfig downloadFolderPath]: Error converting FSRef to Path: FSRefMakePath() failed: %@", OANameForInternetConfigErrorCode(error));
        return nil;
    }
    
    // FSRefMakePath() is documented to return a UTF8 string (in Files.h and in Apple TN2078). It's not clear whether this is just because it returns a filesystem representation and filesystem representations are UTF8, or whether it would continue to return UTF8 strings even if NSFileManager's fileSystemRepresentation were to change.
    return [NSString stringWithUTF8String:(char *)path];
}
#endif

// Mappings between type/creator codes and filename extensions

- (NSArray *)mapEntries;
{
    // TODO: -mapEntries not finished
    return nil;
}

- (OAInternetConfigMapEntry *)mapEntryForFilename:(NSString *)filename;
{
    OSStatus error;
    ICMapEntry mapEntry;
    Str255 filenamePascalString;

    CFStringGetPascalString((CFStringRef)filename, filenamePascalString, sizeof(filenamePascalString) - 1, kCFStringEncodingMacRoman);
    error = ICMapFilename(internetConfigInstance, filenamePascalString, &mapEntry);
    if (error != noErr)
        [NSException raise:@"OAInternetConfigException" format:NSLocalizedStringFromTableInBundle(@"ICMapFilename returned an error for file %@: %@", @"OmniAppKit", [OAInternetConfig bundle], "internet config error"), filename, OANameForInternetConfigErrorCode(error)];
    // TODO: -mapEntryForFilename: not finished
    return nil;
}

- (OAInternetConfigMapEntry *)mapEntryForTypeCode:(long)fileTypeCode creatorCode:(long)fileCreatorCode hintFilename:(NSString *)filename;
{
    // TODO: -mapEntryForTypeCode:creatorCode:hintFilename: not finished
    return nil;
}

- (void)editPreferencesFocusOnKey:(NSString *)keyString;
{
    OSStatus error;
    Str255 keyPascalString;

    if (keyString == nil)
        keyString = @"";
    CFStringGetPascalString((CFStringRef)keyString, keyPascalString, sizeof(keyPascalString) - 1, kCFStringEncodingMacRoman);
    error = ICEditPreferences(internetConfigInstance, keyPascalString);
    if (error != noErr)
        [NSException raise:@"OAInternetConfigException" format:NSLocalizedStringFromTableInBundle(@"Error editing InternetConfig preferences for key %@: %@", @"OmniAppKit", [OAInternetConfig bundle], "internet config error"), keyString, OANameForInternetConfigErrorCode(error)];
}

// Low-level access

- (void)beginReadOnlyAccess;
{
    OSStatus error;

    error = ICBegin(internetConfigInstance, icReadOnlyPerm);
    if (error != noErr)
        [NSException raise:@"OAInternetConfigException" format:NSLocalizedStringFromTableInBundle(@"Error opening InternetConfig for read-only access: %@", @"OmniAppKit", [OAInternetConfig bundle], "internet config error"), OANameForInternetConfigErrorCode(error)];
}

- (void)beginReadWriteAccess;
{
    OSStatus error;

    error = ICBegin(internetConfigInstance, icReadWritePerm);
    if (error != noErr)
        [NSException raise:@"OAInternetConfigException" format:NSLocalizedStringFromTableInBundle(@"Error opening InternetConfig for read-write access: %@", @"OmniAppKit", [OAInternetConfig bundle], "internet config error"), OANameForInternetConfigErrorCode(error)];
}

- (void)endAccess;
{
    OSStatus error;

    error = ICEnd(internetConfigInstance);
    if (error != noErr)
        [NSException raise:@"OAInternetConfigException" format:NSLocalizedStringFromTableInBundle(@"ICEnd returned an error: %@", @"OmniAppKit", [OAInternetConfig bundle], "internet config error"), OANameForInternetConfigErrorCode(error)];
}

- (NSArray *)allPreferenceKeys;
{
    OSStatus error;
    NSMutableArray *keys;
    long preferenceIndex, preferenceCount;

    [self beginReadOnlyAccess];
    error = ICCountPref(internetConfigInstance, &preferenceCount);
    if (error != noErr)
        [NSException raise:@"OAInternetConfigException" format:NSLocalizedStringFromTableInBundle(@"ICCountPref returned an error: %@", @"OmniAppKit", [OAInternetConfig bundle], "internet config error"), OANameForInternetConfigErrorCode(error)];
    keys = [NSMutableArray arrayWithCapacity:preferenceCount];
    for (preferenceIndex = 0; preferenceIndex < preferenceCount; preferenceIndex++) {
        Str255 keyPascalString;
        NSString *keyString;

        error = ICGetIndPref(internetConfigInstance, preferenceIndex + 1, keyPascalString);
        if (error != noErr)
            [NSException raise:@"OAInternetConfigException" format:NSLocalizedStringFromTableInBundle(@"ICGetIndPref %d/%d returned an error: %@", @"OmniAppKit", [OAInternetConfig bundle], "internet config error"), preferenceIndex + 1, preferenceCount, OANameForInternetConfigErrorCode(error)];
        keyString = (NSString *)CFStringCreateWithPascalString(NULL, keyPascalString, kCFStringEncodingMacRoman);
        [keys addObject:keyString];
        [keyString release];
    }
    [self endAccess];
    return keys;
}

- (NSData *)dataForPreferenceKey:(NSString *)preferenceKey error:(NSError **)outError;
{
    if (preferenceKey == nil || ([preferenceKey length] == 0))
        [NSException raise:NSInvalidArgumentException format:@"preferenceKey may not be nil or empty"];

    Str255 keyPascalString;
    CFStringGetPascalString((CFStringRef)preferenceKey, keyPascalString, sizeof(keyPascalString) - 1, kCFStringEncodingMacRoman);
    
    ICAttr itemAttributes;
    Handle itemDataHandle = NewHandle(256);
    OSStatus error = ICFindPrefHandle(internetConfigInstance, keyPascalString, &itemAttributes, itemDataHandle);

    NSData *itemData = nil;
    if (error == noErr) {
        HLock(itemDataHandle);
        itemData = [NSData dataWithBytes:*itemDataHandle length:GetHandleSize(itemDataHandle)];
        HUnlock(itemDataHandle);
        DisposeHandle(itemDataHandle);
        
        return itemData;
    } else {
        DisposeHandle(itemDataHandle);
        
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Error reading InternetConfig preference for key %@", @"OmniAppKit", OMNI_BUNDLE, "internet config error"), preferenceKey];
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"ICFindPrefHandle returned %d -- %@", @"OmniAppKit", OMNI_BUNDLE, "internet config error"), error, OANameForInternetConfigErrorCode(error)];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey, reason, NSLocalizedFailureReasonErrorKey, nil];
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:error userInfo:userInfo];
        return nil;
    }
}

// LaunchServices won't pass URLs larger than 1K.
#define MAX_LAUNCH_SERVICES_URL_LENGTH 1023

- (BOOL)launchMailTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy subject:(NSString *)subject body:(NSString *)body error:(NSError **)outError
{
    return [self launchMailTo:receiver carbonCopy:carbonCopy blindCarbonCopy:nil subject:subject body:body error:outError];
}

- (BOOL)launchMailTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy blindCarbonCopy:(NSString *)blindCarbonCopy subject:(NSString *)subject body:(NSString *)body error:(NSError **)outError;
{
    // Look up the user mail app in InternetConfig (LaunchServices doesn't return app names for mailto urls for some reason).
    NSString *mailApp = [self helperApplicationForScheme:@"mailto"];
    if (mailApp == nil)
        mailApp = @"Mail";

    NSString *url = [self mailtoURLWithTo:receiver carbonCopy:carbonCopy blindCarbonCopy:blindCarbonCopy subject:subject];
    // Using AppleScript for sending mail can be problematic, so only use it if the URL is so long that LaunchServices won't work.
    if ([NSString isEmptyString:body]) {
        if ([url length] > MAX_LAUNCH_SERVICES_URL_LENGTH) {
            if ([mailApp containsString:@"entourage" options:NSCaseInsensitiveSearch])
                [self sendMailViaEntourageTo:receiver carbonCopy:carbonCopy blindCarbonCopy:blindCarbonCopy subject:subject body:nil];
            else
                [self sendMailViaAppleScriptWithApplication:mailApp mailtoURL:url codedBody:nil];
            return YES;
        } else {
            return [self launchURL:url error:outError];
        }
    } else {
        body = [body stringByReplacingCharactersInSet:[NSCharacterSet characterSetWithRange:NSMakeRange('\n', 1)] withString:@"\r"];

        NSString *urlCodedBody = [NSString encodeURLString:body asQuery:NO leaveSlashes:NO leaveColons:NO];

        if ([url length] + [urlCodedBody length] + 6 > MAX_LAUNCH_SERVICES_URL_LENGTH) {
            if ([mailApp containsString:@"entourage" options:NSCaseInsensitiveSearch])
                [self sendMailViaEntourageTo:receiver carbonCopy:carbonCopy blindCarbonCopy:blindCarbonCopy subject:subject body:body];
            else
                [self sendMailViaAppleScriptWithApplication:mailApp mailtoURL:url codedBody:urlCodedBody];
            return YES;
        } else {
            url = [[url stringByAppendingString:@"&body="] stringByAppendingString:urlCodedBody];
            return [self launchURL:url error:outError];
        }
    }
}

static BOOL _executeScript(NSString *source)
{
    NSAppleScript *runner = [[[NSAppleScript alloc] initWithSource:source] autorelease];
    NSDictionary *errorDict = nil;
    if (![runner compileAndReturnError:&errorDict]) {
        NSLog(@"Error compiling mail to script: %@", errorDict);
        return NO;
    }
    if (![runner executeAndReturnError:&errorDict]) {
        NSLog(@"Error running mail to script: %@", errorDict);
        return NO;
    }
    
    return YES;
}

- (BOOL)launchMailTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy blindCarbonCopy:(NSString *)blindCarbonCopy subject:(NSString *)subject body:(NSString *)body attachments:(NSArray *)attachmentFilenames;
{
    NSMutableString *script = nil;
    unsigned int attachmentIndex, attachmentCount = [attachmentFilenames count];
    
    NSString *mailApp = [self helperApplicationForScheme:@"mailto"];

    if (!mailApp || [mailApp isEqualToString:@"Mail"]) {
        script = [NSMutableString stringWithFormat:@"tell application \"%@\"\n set m to a reference to (make new outgoing message at beginning of outgoing messages)\rtell m\n", mailApp];
        [script appendFormat:@"make new to recipient at beginning of to recipients with properties {address: \"%@\"}\n", receiver];
        if (carbonCopy != nil) 
            [script appendFormat:@"make new cc recipient at beginning of cc recipients with properties {address: \"%@\"}\n", carbonCopy];
        if (blindCarbonCopy != nil)
            [script appendFormat:@"make new bcc recipient at beginning of bcc recipients with properties {address: \"%@\"}\n", blindCarbonCopy];
        [script appendFormat:@"set subject to \"%@\"\n", subject];
        [script appendFormat:@"set content to \"%@\"\n", body];

        if (attachmentCount) {
            [script appendString:@"tell content\n"];
            for (attachmentIndex = 0; attachmentIndex < attachmentCount; attachmentIndex++) {
                [script appendFormat:@"make new attachment with properties {file name: \"%@\"} at after last character\n", [attachmentFilenames objectAtIndex:attachmentIndex]];
            }
            [script appendString:@"end tell\n"];
        }
        [script appendString:@"set visible to true\n end tell\n activate\n end tell\n"];
    } else if ([mailApp isEqualToString:@"Mailsmith"]) {
        // <sgehrman@cocoatech.com>
        script = [NSMutableString stringWithFormat:@"tell application \"%@\"\n set m to make new message window\n", mailApp]; 
        [script appendString: @"activate\n"]; 
        [script appendString: @"tell m\n"]; 
        [script appendFormat:@"make new to_recipient at end with properties {address: \"%@\"}\n", receiver]; 
        if (carbonCopy != nil) 
            [script appendFormat:@"make new cc_recipient at end with properties {address: \"%@\"}\n", carbonCopy]; 
        if (blindCarbonCopy != nil) 
            [script appendFormat:@"make new bcc_recipient at end with properties {address: \"%@\"}\n", blindCarbonCopy]; 
        [script appendFormat:@"set subject to \"%@\"\n", subject]; 
        [script appendFormat:@"set contents to \"%@\"\n", body]; 

        for (attachmentIndex = 0; attachmentIndex < attachmentCount; attachmentIndex++) {
            [script appendFormat:@"make new enclosure at end with properties {file: posix file \"%@\"}\n", [attachmentFilenames objectAtIndex:attachmentIndex]]; 
        }
        
        [script appendString:@"end tell\n"];      // end tell message 
        [script appendString:@"activate\n"]; 
        [script appendString:@"end tell\n"];      // end tell Mailsmith 
    } else if ([mailApp containsString:@"entourage" options:NSCaseInsensitiveSearch]) {
        script = [NSMutableString stringWithFormat:@"tell application \"%@\"\n set m to make new draft window with properties {%%@}\nactivate\nend tell\n", mailApp]; 
        NSMutableArray *properties = [NSMutableArray array];
            
        
        [properties addObject:[NSString stringWithFormat:@"to recipients: \"%@\"", receiver]];
        if (carbonCopy != nil) 
            [properties addObject:[NSString stringWithFormat:@"CC recipients: \"%@\"", carbonCopy]];
        if (blindCarbonCopy != nil) 
            [properties addObject:[NSString stringWithFormat:@"BCC recipients: \"%@\"", blindCarbonCopy]];
        [properties addObject:[NSString stringWithFormat:@"subject: \"%@\"", subject]];
        [properties addObject:[NSString stringWithFormat:@"content: \"%@\"", body]];
        if (0 < attachmentCount) 
        {
            NSFileManager *defaultManager = [NSFileManager defaultManager];
            NSMutableArray *attachmentPaths = [NSMutableArray array];
            NSString *scratchDirectoryPath = nil;
            
            for (attachmentIndex = 0; attachmentIndex < attachmentCount; attachmentIndex++)  {
                NSString *filename = [attachmentFilenames objectAtIndex:attachmentIndex];
                BOOL isDirectory = NO;
                
                if ([defaultManager fileExistsAtPath:filename isDirectory:&isDirectory]) {
                    scratchDirectoryPath = [defaultManager scratchDirectoryPath];
                    if (isDirectory) {
                        // Entourage won't zip up directories or anything nice.  Instead it will crash.
                        NSTask *zipTask = [[NSTask alloc] init];
                        [zipTask setLaunchPath:@"/usr/bin/zip"];
                        [zipTask setCurrentDirectoryPath:[filename stringByDeletingLastPathComponent]];
                        [zipTask setStandardOutput:[NSPipe pipe]];
                        
                        NSString *outfile = [[[filename lastPathComponent] stringByDeletingPathExtension] stringByAppendingString:@"-######.zip"];
                        outfile = [defaultManager tempFilenameFromHashesTemplate:outfile];
                        outfile = [scratchDirectoryPath stringByAppendingPathComponent:outfile];
                        
                        [zipTask setArguments:[NSArray arrayWithObjects:@"-r", outfile, [filename lastPathComponent], nil]];
                        [zipTask launch];
                        [zipTask waitUntilExit];
                        int status = [zipTask terminationStatus];
                        if (status != 0)
                            NSLog(@"[%@ %s] - Failed to zip directory file %@ with status (%d) for attachment to Entourage mail message.  File will not be attached", [self class], _cmd, filename, status);
                        else 
                            [attachmentPaths addObject:OAFragmentedAppleScriptStringForString([NSString stringWithFormat:@"%@", [outfile hfsPathFromPOSIXPath]])]; 
                        
                        [zipTask release];
                    } else
                        [attachmentPaths addObject:OAFragmentedAppleScriptStringForString([filename hfsPathFromPOSIXPath])]; 
                } else
                    NSLog(@"[%@ %s] - File %@ does not exist and will not be attached", [self class], _cmd, filename);
            }
            
            if ([attachmentPaths count])
                [properties addObject:[NSString stringWithFormat:@"attachment: {%@}", [attachmentPaths componentsJoinedByString:@", "]]];
        }
        
        script = [NSString stringWithFormat:script, [properties componentsJoinedByString:@", "]];
    }

    if (!script)
        return NO;
    
    return _executeScript(script);
}

@end

@implementation OAInternetConfig (Private)

- (NSString *)_helperKeyNameForScheme:(NSString *)scheme;
{
    return [helperKeyPrefix stringByAppendingString:scheme];
}

- (void)sendMailViaEntourageTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy blindCarbonCopy:(NSString *)blindCarbonCopy subject:(NSString *)subject body:(NSString *)body;
{
    BOOL needComma = NO;
    NSMutableString *script;

    script = [NSMutableString stringWithFormat:@"tell application \"Microsoft Entourage\"\n make new draft window with properties {"];
    if (receiver) {
        [script appendString:@"to recipients: "];
        [script appendString:OAFragmentedAppleScriptStringForString(receiver)];
        needComma = YES;
    }
    if (carbonCopy) {
        if (needComma)
            [script appendString:@", "];
        [script appendString:@"CC recipients: "];
        [script appendString:OAFragmentedAppleScriptStringForString(carbonCopy)];
        needComma = YES;
    }
    if (blindCarbonCopy) {
        if (needComma)
            [script appendString:@", "];
        [script appendString:@"BCC recipients: "];
        [script appendString:OAFragmentedAppleScriptStringForString(blindCarbonCopy)];
        needComma = YES;
    }
    if (subject) {
        if (needComma)
            [script appendString:@", "];
        [script appendString:@"subject: "];
        [script appendString:OAFragmentedAppleScriptStringForString(subject)];
        needComma = YES;
    }
    if (body) {
        if (needComma)
            [script appendString:@", "];
        [script appendString:@"content: "];
        [script appendString:OAFragmentedAppleScriptStringForString(body)];
    }

    [script appendString:@"}\nactivate\nend tell"];

    // NSLog(@"script = %@", script);

    _executeScript(script);
}

- (void)sendMailViaAppleScriptWithApplication:(NSString *)mailApp mailtoURL:(NSString *)url codedBody:(NSString *)body;
{
    OBPRECONDITION(mailApp != nil);
    OBPRECONDITION(url != nil);

    NSMutableString *script = [NSMutableString stringWithFormat:@"tell application \"%@\"\n %@event GURLGURL%@ %@", mailApp, [NSString leftPointingDoubleAngleQuotationMarkString], [NSString rightPointingDoubleAngleQuotationMarkString], OAFragmentedAppleScriptStringForString(url)];
    /* Since it's pretty hard to read, here's an example of what the preceding stament produces:
           tell application "Mail"
           <<event GURLGURL>> "mailto:foo@bar.com?carbonCopy=blegga@bar.com&subject=stuff
       except it uses real double-angle-quotes.
    */
    
    if (body) {
        [script appendString:@" & \"&body=\" & "];
        [script appendString:OAFragmentedAppleScriptStringForString(body)];
    }

    [script appendString:@"\nactivate\nend tell"];

    //NSLog(@"script = %@", script);

    _executeScript(script);
}

#define NEW_ARG(url) do { \
    [url appendString:firstArgument ? @"?" : @"&"]; \
        firstArgument = NO; \
} while (0)

- (NSString *)mailtoURLWithTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy blindCarbonCopy:(NSString *)blindCarbonCopy subject:(NSString *)subject;
{
    NSMutableString *mailtoURL;
    NSString *urlCodedString;
    BOOL firstArgument;

    firstArgument = YES;
    mailtoURL = [NSMutableString stringWithString:@"mailto:"];
    urlCodedString = [NSString encodeURLString:receiver asQuery:NO leaveSlashes:NO leaveColons:NO];
    [mailtoURL appendString:urlCodedString];

    if (carbonCopy) {
        NEW_ARG(mailtoURL);
        urlCodedString = [NSString encodeURLString:carbonCopy asQuery:NO leaveSlashes:NO leaveColons:NO];
        [mailtoURL appendFormat:@"cc=%@", urlCodedString];
    }

    if (blindCarbonCopy) {
        NEW_ARG(mailtoURL);
        urlCodedString = [NSString encodeURLString:blindCarbonCopy asQuery:NO leaveSlashes:NO leaveColons:NO];
        [mailtoURL appendFormat:@"bcc=%@", urlCodedString];
    }

    if (subject) {
        NEW_ARG(mailtoURL);
        urlCodedString = [NSString encodeURLString:subject asQuery:NO leaveSlashes:NO leaveColons:NO];
        [mailtoURL appendFormat:@"subject=%@", urlCodedString];
    }

    return mailtoURL;
}

static NSString *OAFragmentedAppleScriptStringForString(NSString *string)
{
    // AppleScript does not handle string constants longer than 32K.  This can be avoided by using the string concatenation operator.  We'll concatenate the body text with the rest of the URL string to make sure that the rest of the URL doesn't blow the 32K limit in conjunction with the first chunk of body text.
    // We'll be a little more conservative and only use 16k character strings.
#define APPLE_SCRIPT_MAX_STRING_LENGTH (unsigned)(16*1024)

    NSMutableString *fragmentedString;
    unsigned int stringLength, stringIndex;
    BOOL firstTime;

    string = [string stringByReplacingCharactersInSet:[NSCharacterSet characterSetWithRange:NSMakeRange('\\', 1)] withString:@"\\\\"];
    string = [string stringByReplacingCharactersInSet:[NSCharacterSet characterSetWithRange:NSMakeRange('"', 1)] withString:@"\\\""];

    fragmentedString = [NSMutableString string];
    stringLength = [string length];
    stringIndex = 0;
    firstTime = YES;
    
    while (stringIndex < stringLength) {
        NSString *fragment;
        unsigned int fragmentLength;

        fragmentLength = MIN(stringLength - stringIndex, APPLE_SCRIPT_MAX_STRING_LENGTH);

        fragment = [string substringWithRange:NSMakeRange(stringIndex, fragmentLength)];
        if (firstTime)
            [fragmentedString appendFormat:@"\"%@\" ", fragment];
        else
            [fragmentedString appendFormat:@"& \"%@\" ", fragment];
        firstTime = NO;
        stringIndex += fragmentLength;
    }

    return fragmentedString;
}

static NSString *OANameForInternetConfigErrorCode(OSStatus errorCode)
{
    switch (errorCode) {
        case icPrefNotFoundErr: return @"icPrefNotFoundErr";
        case icPermErr: return @"icPermErr";
        case icPrefDataErr: return @"icPrefDataErr";
        case icInternalErr: return @"icInternalErr";
        case icTruncatedErr: return @"icTruncatedErr";
        case icNoMoreWritersErr: return @"icNoMoreWritersErr";
        case icNothingToOverrideErr: return @"icNothingToOverrideErr";
        case icNoURLErr: return @"icNoURLErr";
        case icConfigNotFoundErr: return @"icConfigNotFoundErr";
        case icConfigInappropriateErr: return @"icConfigInappropriateErr";
        case icProfileNotFoundErr: return @"icProfileNotFoundErr";
        case icTooManyProfilesErr: return @"icTooManyProfilesErr";
        default: return [NSString stringWithFormat:@"<error code %d>", errorCode];
    }
}

@end
