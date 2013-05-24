// Copyright 2000-2005, 2007-2008, 2010-2013 Omni Development, Inc. All rights reserved.
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

@interface OAInternetConfig ()

- (void)sendMailViaEntourageTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy blindCarbonCopy:(NSString *)blindCarbonCopy subject:(NSString *)subject body:(NSString *)body;
- (void)sendMailViaAppleScriptWithApplication:(NSString *)mailApp mailtoURL:(NSString *)url codedBody:(NSString *)body;
- (NSString *)mailtoURLWithTo:(NSString *)receiver carbonCopy:(NSString *)carbonCopy blindCarbonCopy:(NSString *)blindCarbonCopy subject:(NSString *)subject;

static NSString *OAFragmentedAppleScriptStringForString(NSString *string);

@end

@implementation OAInternetConfig

#ifdef OMNI_ASSERTIONS_ON

+ (void)didLoad;
{
    if ([[NSProcessInfo processInfo] isSandboxed]) {
        NSDictionary *entitlements = [[NSProcessInfo processInfo] effectiveCodeSigningEntitlements:NULL];
        
        NSDictionary *scriptingTargets = entitlements[@"com.apple.security.scripting-targets"];
        NSArray *mailAccessGroups = scriptingTargets[@"com.apple.mail"];
        OBASSERT([mailAccessGroups containsObject:@"com.apple.mail.compose"], "Missing scripting target entitlement needed in order to compose feedback message in Mail on Mountain Lion.");
        
        NSArray *appleEventExceptions = entitlements[@"com.apple.security.temporary-exception.apple-events"];
        
        // We can only send apple-events to Entourage and Mailsmith via temporary exceptions
        OBASSERT([appleEventExceptions containsObject:@"com.barebones.mailsmith"], "Missing temporary exception entitlement needed in order to compose feedback message in Mailsmith.");
        OBASSERT([appleEventExceptions containsObject:@"com.microsoft.entourage"], "Missing temporary exception entitlement needed in order to compose feedback message in Entourage.");
    }
}

#endif

+ (OAInternetConfig *)internetConfig;
{
    return [[[self alloc] init] autorelease];
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

- (NSString *)helperApplicationForScheme:(NSString *)scheme;
{
    CFURLRef schemeURL = (CFURLRef)[NSURL URLWithString:[scheme stringByAppendingString:@":"]];
    CFURLRef helperApplicationURL;
    OSStatus status = LSGetApplicationForURL(schemeURL, kLSRolesAll, NULL, &helperApplicationURL);
    if (status == noErr) {
        NSString *helperApplicationPath, *helperApplicationName;

        // Check to make sure the registered helper application isn't us
        helperApplicationPath = [(NSURL *)helperApplicationURL path];
        helperApplicationName = [[helperApplicationPath lastPathComponent] stringByDeletingPathExtension];
        return helperApplicationName;
    }

    return nil;
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
    NSUInteger attachmentIndex, attachmentCount = [attachmentFilenames count];
    
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
                            NSLog(@"[%@ %@] - Failed to zip directory file %@ with status (%d) for attachment to Entourage mail message.  File will not be attached", [self class], NSStringFromSelector(_cmd), filename, status);
                        else 
                            [attachmentPaths addObject:OAFragmentedAppleScriptStringForString([NSString stringWithFormat:@"%@", [outfile hfsPathFromPOSIXPath]])]; 
                        
                        [zipTask release];
                    } else
                        [attachmentPaths addObject:OAFragmentedAppleScriptStringForString([filename hfsPathFromPOSIXPath])]; 
                } else
                    NSLog(@"[%@ %@] - File %@ does not exist and will not be attached", [self class], NSStringFromSelector(_cmd), filename);
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

#pragma mark -
#pragma mark Private

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

@end
