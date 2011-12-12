// Copyright 2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFUTI.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#endif

RCS_ID("$Id$");

NSString *OFUTIForFileURLPreferringNative(NSURL *fileURL, NSError **outError)
{
    if (![fileURL isFileURL])
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Argument to OFUTIForFileURL must be a file URL." userInfo:nil];
    
    NSString *path = [fileURL path];
    BOOL isDirectory;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
        if (outError)
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:[NSDictionary dictionaryWithObject:fileURL forKey:NSURLErrorKey]];
        
        return nil;
    }
    
    return OFUTIForFileExtensionPreferringNative([path pathExtension], isDirectory);
}

NSString *OFUTIForFileExtensionPreferringNative(NSString *extension, BOOL isDirectory)
{
    return OFUTIForTagPreferringNative(kUTTagClassFilenameExtension, extension, isDirectory ? kUTTypeDirectory : NULL);
}

NSString *OFUTIForTagPreferringNative(CFStringRef tagClass, NSString *tag, CFStringRef conformingToUTIOrNull)
{
    NSString *mainBundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    OBASSERT_NOTNULL(mainBundleIdentifier);
    
    NSArray *allTypes = NSMakeCollectable(UTTypeCreateAllIdentifiersForTag(tagClass, (CFStringRef)tag, conformingToUTIOrNull));
    NSString *resolvedType = nil;
    
    for (NSString *type in allTypes) {
        resolvedType = [type retain];
        
        NSURL *bundleURL = NSMakeCollectable(UTTypeCopyDeclaringBundleURL((CFStringRef)type));
        if (!bundleURL)
            continue;
        
        NSString *declaringBundleIdentifier = [[NSBundle bundleWithURL:bundleURL] bundleIdentifier];
        
        BOOL isMainBundle = [mainBundleIdentifier isEqual:declaringBundleIdentifier];
        
        [bundleURL release];
        if (isMainBundle)
            break;
    }
    
    [allTypes release];
    return [resolvedType autorelease];
}
