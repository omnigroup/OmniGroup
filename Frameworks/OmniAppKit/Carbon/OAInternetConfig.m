// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAInternetConfig.h>

#import <OmniFoundation/OmniFoundation.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

static NSString *OAFragmentedAppleScriptStringForString(NSString *string);

NSString *OAAppleMailBundleIdentifier = @"com.apple.mail";
NSString *OAMailSmithBundleIdentifier = @"com.barebones.mailsmith";

@implementation OAInternetConfig

#ifdef OMNI_ASSERTIONS_ON

static void _checkProcessEntitlements(void);
static void _checkProcessEntitlements(void)
{
    // Plug-ins don't ask for these entitlements, so don't check for them.
    NSString *pathExtension = NSBundle.mainBundle.bundleURL.pathExtension;
    if ([pathExtension isEqualToString:@"appex"]) {
        return;
    }
    
    if ([[NSProcessInfo processInfo] isSandboxed]) {
        NSDictionary *entitlements = [[NSProcessInfo processInfo] effectiveCodeSigningEntitlements:NULL];
        OBASSERT([entitlements boolForKey:@"com.apple.security.automation.apple-events"], "Sending email requires the com.apple.security.automation.apple-events entitlement under Mojave's hardened runtime.");

        NSDictionary *scriptingTargets = entitlements[@"com.apple.security.scripting-targets"];
        NSArray *mailAccessGroups = scriptingTargets[OAAppleMailBundleIdentifier];
        OBASSERT([mailAccessGroups containsObject:@"com.apple.mail.compose"], "Missing scripting target entitlement needed in order to compose feedback message in Mail on Mountain Lion.");
        
        NSArray *appleEventExceptions = entitlements[@"com.apple.security.temporary-exception.apple-events"];
        
        // We can only send apple-events to Entourage and Mailsmith via temporary exceptions
        OBASSERT([appleEventExceptions containsObject:OAMailSmithBundleIdentifier], "Missing temporary exception entitlement needed in order to compose feedback message in Mailsmith.");
    }
}

OBDidLoad(^{
    _checkProcessEntitlements();
});

#endif

+ (instancetype)internetConfig;
{
    return [[self alloc] init];
}

+ (FourCharCode)applicationSignature;
{
    NSString *bundleSignature = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleSignature"];
    if (!bundleSignature)
        return FOUR_CHAR_CODE('????');
    
    NSData *signatureBytes = [bundleSignature dataUsingEncoding:[NSString defaultCStringEncoding]];
    if (!signatureBytes || ([signatureBytes length] < 4))
        return FOUR_CHAR_CODE('????');
    
    return *(const OSType *)[signatureBytes bytes];
}

- (nullable NSURL *)helperApplicationURLForScheme:(NSString *)scheme;
{
    OBPRECONDITION(![NSString isEmptyString:scheme]);
    if (![scheme hasSuffix:@":"]) {
        scheme = [scheme stringByAppendingString:@":"];
    }
    
    NSURL *schemeURL = [NSURL URLWithString:scheme];
    CFURLRef helperApplicationURL = LSCopyDefaultApplicationURLForURL((__bridge CFURLRef)schemeURL, kLSRolesAll, NULL);
    return CFBridgingRelease(helperApplicationURL);
}

- (nullable NSString *)helperApplicationBundleIdentifierForScheme:(NSString *)scheme;
{
    NSURL *helperApplicationURL = [self helperApplicationURLForScheme:scheme];
    if (helperApplicationURL != nil) {
        NSBundle *mailApplicationBundle = [NSBundle bundleWithURL:helperApplicationURL];
        NSString *bundleId = [mailApplicationBundle bundleIdentifier];

        return bundleId;
    }

    return nil;
}

- (BOOL)launchURL:(nullable NSString *)urlString error:(NSError **)outError;
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

static NSString *OAInternetConfigErrorDomain = @"com.omnigroup.OmniAppKit.OAInternetConfig";

static void HandleAppleScriptError(NSString *source, NSString *message, NSDictionary *errorInfo, NSError **outError)
{
    NSValue *errorRangeValue = [errorInfo objectForKey:NSAppleScriptErrorRange];
    if (errorRangeValue != nil) {
        NSRange errorRange = [errorRangeValue rangeValue];
        source = [source stringByReplacingCharactersInRange:errorRange withString:[NSString stringWithFormat:@"[%@]", [source substringWithRange:errorRange]]];
    }

    NSLog(@"%@: %@\nDetails: %@\nScript:\n===\n%@\n===\n", message, [errorInfo objectForKey:NSAppleScriptErrorMessage], [errorInfo description], source);

    if (outError != NULL)
        *outError = [NSError errorWithDomain:OAInternetConfigErrorDomain code:[[errorInfo objectForKey:NSAppleScriptErrorNumber] intValue] userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[errorInfo objectForKey:NSAppleScriptErrorBriefMessage], NSLocalizedFailureReasonErrorKey, nil]];
}

static BOOL _executeScript(NSString *source, NSError **outError)
{
    NSAppleScript *runner = [[NSAppleScript alloc] initWithSource:source];
    NSDictionary *errorInfo = nil;
    if (![runner compileAndReturnError:&errorInfo]) {
        HandleAppleScriptError(source, @"Error compiling mail script", errorInfo, outError);
        return NO;
    }
    if (![runner executeAndReturnError:&errorInfo]) {
        HandleAppleScriptError(source, @"Error running mail script", errorInfo, outError);
        return NO;
    }
    
    return YES;
}

- (NSString *)_appleMailScriptForMailApp:(NSString *)mailApp receiver:(nullable NSString *)receiver carbonCopy:(nullable NSString *)carbonCopy blindCarbonCopy:(nullable NSString *)blindCarbonCopy subject:(nullable NSString *)subject body:(nullable NSString *)body attachments:(nullable NSArray <NSString *> *)attachmentFilenames;
{
    NSMutableString *script = [NSMutableString stringWithFormat:@"tell application \"%@\"\n set m to a reference to (make new outgoing message)\ntell m\n", mailApp];

    if (receiver != nil) {
        [script appendFormat:@"make new to recipient with properties {address: %@}\n", OAFragmentedAppleScriptStringForString(receiver)];
    }
    if (carbonCopy != nil)
        [script appendFormat:@"make new cc recipient with properties {address: %@}\n", OAFragmentedAppleScriptStringForString(carbonCopy)];
    if (blindCarbonCopy != nil)
        [script appendFormat:@"make new bcc recipient with properties {address: %@}\n", OAFragmentedAppleScriptStringForString(blindCarbonCopy)];
    if (subject != nil)
        [script appendFormat:@"set subject to %@\n", OAFragmentedAppleScriptStringForString(subject)];
    if (body != nil)
        [script appendFormat:@"set content to %@\n", OAFragmentedAppleScriptStringForString(body)];

    if (attachmentFilenames.count != 0) {
        [script appendString:@"tell content\n"];
        for (NSString *attachmentFilename in attachmentFilenames) {
            [script appendFormat:@"make new attachment with properties {file name: posix file (%@)}\n", OAFragmentedAppleScriptStringForString(attachmentFilename)];
        }
        [script appendString:@"end tell\n"];
    }

    [script appendString:@"set visible to true\n end tell\n end tell\n"];

    return script;
}

- (NSString *)_mailSmithScriptForMailApp:(NSString *)mailApp receiver:(nullable NSString *)receiver carbonCopy:(nullable NSString *)carbonCopy blindCarbonCopy:(nullable NSString *)blindCarbonCopy subject:(nullable NSString *)subject body:(nullable NSString *)body attachments:(nullable NSArray <NSString *> *)attachmentFilenames;
{
    // <sgehrman@cocoatech.com>
    NSMutableString *script = [NSMutableString stringWithFormat:@"tell application \"%@\"\n set m to make new message window\n", mailApp];
    [script appendString:@"activate\n"];
    [script appendString:@"tell m\n"];

    if (receiver != nil) {
        [script appendFormat:@"make new to_recipient at end with properties {address: %@}\n", OAFragmentedAppleScriptStringForString(receiver)];
    }
    if (carbonCopy != nil)
        [script appendFormat:@"make new cc_recipient at end with properties {address: %@}\n", OAFragmentedAppleScriptStringForString(carbonCopy)];
    if (blindCarbonCopy != nil)
        [script appendFormat:@"make new bcc_recipient at end with properties {address: %@}\n", OAFragmentedAppleScriptStringForString(blindCarbonCopy)];
    if (subject != nil)
        [script appendFormat:@"set subject to %@\n", OAFragmentedAppleScriptStringForString(subject)];
    if (body != nil)
        [script appendFormat:@"set contents to %@\n", OAFragmentedAppleScriptStringForString(body)];

    for (NSString *attachmentFilename in attachmentFilenames) {
        [script appendFormat:@"make new enclosure at end with properties {file: posix file (%@)}\n", OAFragmentedAppleScriptStringForString(attachmentFilename)];
    }

    [script appendString:@"end tell\n"];      // end tell message
    [script appendString:@"activate\n"];
    [script appendString:@"end tell\n"];      // end tell Mailsmith

    return script;
}

- (BOOL)launchMailApplicationWithBundleIdentifier:(NSString *)mailAppIdentifier to:(nullable NSString *)receiver carbonCopy:(nullable NSString *)carbonCopy blindCarbonCopy:(nullable NSString *)blindCarbonCopy subject:(nullable NSString *)subject body:(nullable NSString *)body attachments:(nullable NSArray <NSString *> *)attachmentFilenames error:(NSError **)outError;
{
    NSString *script = nil;

    if (mailAppIdentifier == nil) {
        mailAppIdentifier = OAAppleMailBundleIdentifier;
    }
        
    if ([mailAppIdentifier isEqualToString:OAAppleMailBundleIdentifier]) {
        script = [self _appleMailScriptForMailApp:@"Mail" receiver:receiver carbonCopy:carbonCopy blindCarbonCopy:blindCarbonCopy subject:subject body:body attachments:attachmentFilenames];
    } else if ([mailAppIdentifier isEqualToString:OAMailSmithBundleIdentifier]) {
        script = [self _mailSmithScriptForMailApp:@"MailSmith" receiver:receiver carbonCopy:carbonCopy blindCarbonCopy:blindCarbonCopy subject:subject body:body attachments:attachmentFilenames];
    }

    if (script == nil) {
        if (attachmentFilenames.count == 0) {
            // If we're not trying to attach a file, just use a mailto URL
            NSString *urlString = [NSString stringWithFormat:@"mailto:%@?subject=%@", (receiver ?: @""), [NSString encodeURLString:subject asQuery:NO leaveSlashes:NO leaveColons:NO]];
            if (![NSString isEmptyString:carbonCopy])
            urlString = [urlString stringByAppendingFormat:@"&cc=%@", [NSString encodeURLString:carbonCopy asQuery:NO leaveSlashes:NO leaveColons:NO]];
            if (![NSString isEmptyString:blindCarbonCopy])
            urlString = [urlString stringByAppendingFormat:@"&bcc=%@", [NSString encodeURLString:blindCarbonCopy asQuery:NO leaveSlashes:NO leaveColons:NO]];
            if (![NSString isEmptyString:body])
            urlString = [urlString stringByAppendingFormat:@"&body=%@", [NSString encodeURLString:body asQuery:NO leaveSlashes:NO leaveColons:NO]];
            return [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlString]];
        } else {
            // Fall back on using Mail if we need to attach a file
            script = [self _appleMailScriptForMailApp:@"Mail" receiver:receiver carbonCopy:carbonCopy blindCarbonCopy:blindCarbonCopy subject:subject body:body attachments:attachmentFilenames];
            mailAppIdentifier = OAAppleMailBundleIdentifier;
        }
    }

    OBASSERT(script != nil);

    if (!_executeScript(script, outError))
        return NO;

    CFErrorRef error = NULL;
    CFArrayRef mailURLs = LSCopyApplicationURLsForBundleIdentifier((__bridge CFStringRef _Nonnull)(mailAppIdentifier), &error);
    if (mailURLs == NULL) {
        if (outError != NULL)
            *outError = (__bridge NSError *)(error);
        CFRelease(error);
        return NO;
    }
    
    OBASSERT(CFArrayGetCount(mailURLs) > 0);
    NSURL *mailURL = CFArrayGetValueAtIndex(mailURLs, 0);
    CFRelease(mailURLs);

    // Our sandbox doesn't let us activate Mail via AppleScript anymore, so we do this via NSWorkspace instead (otherwise the compose window won't come forward).
#if defined(MAC_OS_X_VERSION_10_15)
    if (@available(macOS 10.15, *)) {
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:mailURL configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:NULL];
    } else {
        NSString *mailApp = [mailURL path];
        [[NSWorkspace sharedWorkspace] launchApplication:mailApp];
    }
#else
    NSString *mailApp = [mailURL path];
    [[NSWorkspace sharedWorkspace] launchApplication:mailApp];
#endif
    
    return YES;
}

- (BOOL)launchMailTo:(nullable NSString *)receiver carbonCopy:(nullable NSString *)carbonCopy blindCarbonCopy:(nullable NSString *)blindCarbonCopy subject:(nullable NSString *)subject body:(nullable NSString *)body attachments:(nullable NSArray <NSString *> *)attachmentFilenames error:(NSError **)outError;
{
    NSString *mailAppIdentifier = [self helperApplicationBundleIdentifierForScheme:@"mailto"];
    return [self launchMailApplicationWithBundleIdentifier:mailAppIdentifier to:receiver carbonCopy:carbonCopy blindCarbonCopy:blindCarbonCopy subject:subject body:body attachments:attachmentFilenames error:outError];
}

- (BOOL)launchMailTo:(nullable NSString *)receiver carbonCopy:(nullable NSString *)carbonCopy subject:(nullable NSString *)subject body:(nullable NSString *)body error:(NSError **)outError
{
    return [self launchMailTo:receiver carbonCopy:carbonCopy blindCarbonCopy:nil subject:subject body:body attachments:nil error:outError];
}

- (BOOL)launchMailTo:(nullable NSString *)receiver carbonCopy:(nullable NSString *)carbonCopy blindCarbonCopy:(nullable NSString *)blindCarbonCopy subject:(nullable NSString *)subject body:(nullable NSString *)body error:(NSError **)outError;
{
    return [self launchMailTo:receiver carbonCopy:carbonCopy blindCarbonCopy:blindCarbonCopy subject:subject body:body attachments:nil error:outError];
}

@end

static NSString *OAFragmentedAppleScriptStringForString(NSString *string)
{
    if ([NSString isEmptyString:string])
        return @"\"\"";

    // AppleScript does not handle string constants longer than 32K.  This can be avoided by using the string concatenation operator.  We'll concatenate the body text with the rest of the URL string to make sure that the rest of the URL doesn't blow the 32K limit in conjunction with the first chunk of body text.
    // We'll be a little more conservative and only use 16k character strings.
#ifdef DEBUG_kc0
#define APPLE_SCRIPT_MAX_STRING_LENGTH (unsigned)(1)
#else
#define APPLE_SCRIPT_MAX_STRING_LENGTH (unsigned)(16*1024)
#endif

    NSMutableString *fragmentedString;
    NSUInteger stringLength, stringIndex;
    BOOL firstTime;

    string = [string stringByReplacingCharactersInSet:[NSCharacterSet characterSetWithRange:NSMakeRange('\\', 1)] withString:@"\\\\"];
    string = [string stringByReplacingCharactersInSet:[NSCharacterSet characterSetWithRange:NSMakeRange('"', 1)] withString:@"\\\""];

    fragmentedString = [NSMutableString string];
    stringLength = [string length];
    stringIndex = 0;
    firstTime = YES;
    
    while (stringIndex < stringLength) {
        NSUInteger fragmentLength = MIN(stringLength - stringIndex, APPLE_SCRIPT_MAX_STRING_LENGTH);
        while (stringIndex + fragmentLength < stringLength && [string characterAtIndex:stringIndex + fragmentLength - 1] == '\\')
            fragmentLength++; // Don't split up a backslash-quoted character sequence

        NSString *fragment = [string substringWithRange:NSMakeRange(stringIndex, fragmentLength)];
        if (firstTime)
            [fragmentedString appendFormat:@"\"%@\" ", fragment];
        else
            [fragmentedString appendFormat:@"& \"%@\" ", fragment];
        firstTime = NO;
        stringIndex += fragmentLength;
    }

    return fragmentedString;
}
