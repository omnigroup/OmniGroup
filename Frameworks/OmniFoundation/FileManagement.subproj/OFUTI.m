// Copyright 2011-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFUTI.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#define SYSTEM_TYPE_BUNDLE_IDENTIFIER @"com.apple.MobileCoreServices"
#else
#import <OmniFoundation/OFController.h>
#define SYSTEM_TYPE_BUNDLE_IDENTIFIER @"com.apple.LaunchServices"
#endif

RCS_ID("$Id$");

NSString * const OFDirectoryPathExtension = @"folder";

// These dictionaries map from tag class (NSString *) to a dictionary whose keys are tag values (NSString *) and whose values are arrays of type identifiers (NSString *) that have claimed that tag.
// Note that it is a bad idea in general for multiple types to claim the same tag, but we have existing apps that declare multiple types with the same file extension (package vs. flat files). This data structure doesn't prohibit inadvisable scenarios, but the lookup and/or creation functions will warn if multiple directory or flat file types are declared for the same tag, or if a type is declared for a tag that conforms to neither public.data or public.directory.
//
// Ex:
// {
//   kUTTagClassFilenameExtension = {
//     "oo3" = (
//       "com.omnigroup.omnioutliner3-package",
//       "com.omnigroup.omnioutliner3"
//     ),
//     "opml" = (
//       "org.opml"
//     )
//   },
//   kUTTagClassMIMEType = {
//     ...
//   },
//   ...
// }
static NSDictionary *MainBundleExportedTypeDeclarationsByTag;
static NSDictionary *MainBundleImportedTypeDeclarationsByTag;

static BOOL OFUTIDiagnosticsEmitted = NO;

#define OFUTI_DIAG(fmt, ...) \
    do { \
        NSLog(@"OFUTI: " fmt, __VA_ARGS__); \
        OFUTIDiagnosticsEmitted = YES; \
    } while (0)

// Returns a +1 retained NSDictionary transformation of the provided array of type declarations (kUT{Exported,Imported}TypeDeclarationsKey) into the form described above.
static NSDictionary *CreateTagDictionaryFromTypeDeclarations(NSArray *typeDeclarations)
{
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    
    // A type declaration is a dictionary...
    for (NSDictionary *declaration in typeDeclarations) {
        // ...with a string value for kUTTypeIdentifierKey...
        NSString *identifier = [declaration objectForKey:(NSString *)kUTTypeIdentifierKey];
        if ([identifier isKindOfClass:[NSString class]])
            identifier = [identifier lowercaseString];
        else {
            OFUTI_DIAG(@"Type declaration identifier must be a string; found \"%@\" instead.", identifier);
            continue;
        }
        
        // ...and a tag specification dictionary as a value for kUTTypeTagSpecificationKey.
        NSDictionary *tagSpecs = [declaration objectForKey:(NSString *)kUTTypeTagSpecificationKey];
        if (!tagSpecs)
            continue;
        
        // A tag specification maps a string tag class...
        for (NSString *tagClass in [tagSpecs allKeys]) {
            // ...to either a string tag value or an array of string tag values.
            NSArray *tagValues;
            
            NSObject *declaredValue = [tagSpecs objectForKey:tagClass];
            if ([declaredValue isKindOfClass:[NSArray class]])
                tagValues = (NSArray *)declaredValue;
            else if ([declaredValue isKindOfClass:[NSString class]])
                tagValues = [NSArray arrayWithObject:declaredValue];
            else {
                OFUTI_DIAG(@"Tag declaration for class \"%@\" of type identifier \"%@\" must be either a string or an array of strings; found \"%@\" instead.", tagClass, identifier, declaredValue);
                continue; // skip to next tag class
            }
            
            NSMutableDictionary *classDict = [result objectForKey:tagClass];
            if (!classDict) {
                classDict = [[NSMutableDictionary alloc] init];
                [result setObject:classDict forKey:tagClass];
                [classDict release];
            }
            
            for (NSString *value in tagValues) {
                if (!([value isKindOfClass:[NSString class]])) {
                    OFUTI_DIAG(@"Tag declaration for class \"%@\" of type identifier \"%@\" must be a string; found \"%@\" instead.", tagClass, identifier, value);
                    continue; // skip this tag value
                }
                
                value = [value lowercaseString];
                
                // Our dictionary maps from tag values to arrays, even though ideally the array only contains one object.
                NSMutableArray *mappedIdentifiers = [classDict objectForKey:value];
                if (!mappedIdentifiers) {
                    mappedIdentifiers = [[NSMutableArray alloc] initWithObjects:(id[]){identifier} count:1];
                    [classDict setObject:mappedIdentifiers forKey:value];
                    [mappedIdentifiers release];
                } else {
                    BOOL conformsToPublicData = UTTypeConformsTo((__bridge CFStringRef)identifier, kUTTypeData);
                    BOOL conformsToPublicDirectory = UTTypeConformsTo((__bridge CFStringRef)identifier, kUTTypeDirectory);
                    
                    if (!conformsToPublicData && !conformsToPublicDirectory) {
                        OFUTI_DIAG(@"Type declaration for type \"%@\" does not conform to either \"%@\" or \"%@\"; it should conform to exactly one", identifier, (NSString *)kUTTypeData, (NSString *)kUTTypeDirectory);
                    } else if (conformsToPublicData && conformsToPublicDirectory) {
                        OFUTI_DIAG(@"Type declaration for type \"%@\" conforms to both \"%@\" and \"%@\"; it should conform to exactly one", identifier, (NSString *)kUTTypeData, (NSString *)kUTTypeDirectory);
                    }
                    
                    // Enumerate the existing types declared for this tag and warn if they share the same conformance to the flat-file (public.data) or directory (public.directory) physical type trees.
                    for (NSString *existingIdentifier in mappedIdentifiers) {
                        if ((conformsToPublicData && UTTypeConformsTo((__bridge CFStringRef)existingIdentifier, kUTTypeData))
                            || (conformsToPublicDirectory && UTTypeConformsTo((__bridge CFStringRef)existingIdentifier, kUTTypeDirectory))) {
                            OFUTI_DIAG(@"Conflict detected registering type \"%@\": type \"%@\" has already claimed tag \"%@\" for class \"%@\". Which one is used is undefined.", identifier, existingIdentifier, value, tagClass);
                            break;
                        }
                    }
                    
                    [mappedIdentifiers addObject:identifier];
                }
            }
        }
    }
    
    return result;
}

static void InitializeKnownTypeDictionaries()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Look in +[OFController controllingBundle] to support unit test bundles
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        NSBundle *controllingBundle = [NSBundle mainBundle];
#else
        NSBundle *controllingBundle = [OFController controllingBundle];
#endif
        NSDictionary *infoDictionary = [controllingBundle infoDictionary];
        
        MainBundleExportedTypeDeclarationsByTag = CreateTagDictionaryFromTypeDeclarations([infoDictionary objectForKey:(NSString *)kUTExportedTypeDeclarationsKey]);
        MainBundleImportedTypeDeclarationsByTag = CreateTagDictionaryFromTypeDeclarations([infoDictionary objectForKey:(NSString *)kUTImportedTypeDeclarationsKey]);
        
        // Warn if both the exported and imported type dictionaries both declared types for the same tag.
        NSArray *allTagClasses = [[MainBundleExportedTypeDeclarationsByTag allKeys] arrayByAddingObjectsFromArray:[MainBundleImportedTypeDeclarationsByTag allKeys]];
        for (NSString *tagClass in allTagClasses) {
            NSDictionary *exportedClassDict = [MainBundleExportedTypeDeclarationsByTag objectForKey:tagClass];
            NSDictionary *importedClassDict = [MainBundleImportedTypeDeclarationsByTag objectForKey:tagClass];
            
            [exportedClassDict enumerateKeysAndObjectsUsingBlock:^(id tagValue, id exportedMappedIdentifiers, BOOL *stop) {
                NSArray *importedMappedIdentifiers = [importedClassDict objectForKey:tagValue];
                if (importedMappedIdentifiers)
                    OFUTI_DIAG(@"Conflict detected registering imported type declaration \"%@\": exported type \"%@\" has already claimed tag \"%@\" for class \"%@\". The exported type will be preferred.", [importedMappedIdentifiers objectAtIndex:0], [exportedMappedIdentifiers objectAtIndex:0], tagValue, tagClass);
            }];
        }
        
        // Break in the debugger just once if assertions are enabled, rather than once for each diagnostic message.
        OBASSERT(OFUTIDiagnosticsEmitted == NO);
    });
}

static void EnumerateIdentifiersForTagInDictionary(NSDictionary *dictionary, NSString *tagClass, NSString *tagValue, OFUTIEnumerator enumerator)
{
    BOOL stopEnumerating = NO;
    
    NSDictionary *classDict = [dictionary objectForKey:tagClass];
    NSArray *mappedIdentifiers = [classDict objectForKey:tagValue];
    
    for (NSString *identifier in mappedIdentifiers) {
        enumerator(identifier, &stopEnumerating);
        if (stopEnumerating)
            return;
    }
}

#pragma mark - Public API

NSString *OFUTIForFileURLPreferringNative(NSURL *fileURL, NSError **outError)
{
    if (![fileURL isFileURL])
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Argument to OFUTIForFileURL must be a file URL, not %@", [fileURL absoluteString]] userInfo:nil];
    
    __autoreleasing NSNumber *isDirectory = nil;
    if (![fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:outError])
        return nil;

    return OFUTIForFileExtensionPreferringNative([fileURL pathExtension], isDirectory);
}

NSString *OFUTIForFileExtensionPreferringNative(NSString *extension, NSNumber *isDirectory)
{
    if (isDirectory && [extension isEqualToString:OFDirectoryPathExtension])
        return (OB_BRIDGE NSString *)kUTTypeFolder;
    
    CFStringRef conformingUTI = NULL;
    if (isDirectory && [isDirectory boolValue])
        conformingUTI = kUTTypeDirectory;
    else if (isDirectory && !([isDirectory boolValue]))
        conformingUTI = kUTTypeData;
    
    return OFUTIForTagPreferringNative(kUTTagClassFilenameExtension, extension, conformingUTI);
}

NSString *OFUTIForTagPreferringNative(CFStringRef tagClass, NSString *tagValue, CFStringRef conformingToUTIOrNull)
{
    __block NSString *resolvedType = nil;
    
    OFUTIEnumerateKnownTypesForTagPreferringNative((__bridge NSString *)tagClass, tagValue, (__bridge NSString *)conformingToUTIOrNull, ^(NSString *typeIdentifier, BOOL *stop){
        resolvedType = typeIdentifier;
        *stop = YES;
    });
    
    OBASSERT_NOTNULL(resolvedType); // should have at least gotten a dynamic type
    return resolvedType;
}

void OFUTIEnumerateKnownTypesForTagPreferringNative(NSString *tagClass, NSString *tagValue, NSString *conformingToUTIOrNil, OFUTIEnumerator enumerator)
{
    __block BOOL stopEnumerating = NO;
    
    // Check our Info.plist first, preferring exported types over imported ones.
    InitializeKnownTypeDictionaries();
    
    OB_FOR_ALL(dict, MainBundleExportedTypeDeclarationsByTag, MainBundleImportedTypeDeclarationsByTag) {
        EnumerateIdentifiersForTagInDictionary(dict, tagClass, tagValue, ^(NSString *typeIdentifier, BOOL *stop) {
            if (!conformingToUTIOrNil || UTTypeConformsTo((__bridge CFStringRef)typeIdentifier, (__bridge CFStringRef)conformingToUTIOrNil)) {
                enumerator(typeIdentifier, &stopEnumerating);
                if (stopEnumerating)
                    *stop = YES;
            }
        });
        
        if (stopEnumerating)
            return;
    }
    
    // No luck looking in our own Info.plist. Look through all the definitions Launch Services knows about, but prefer any declarations by CoreServices. We allow the caller to pass a conformingToUTI hint in order to limit the size of and time spent copying this array.
    NSArray *allTypes = CFBridgingRelease(UTTypeCreateAllIdentifiersForTag((__bridge CFStringRef)tagClass, (__bridge CFStringRef)tagValue, (__bridge CFStringRef)conformingToUTIOrNil));
    if (!allTypes)
        return;
    
    // These arrays might hold the last remaining retain on the type identifiers we passed to the enumerator block. Rather than retain/autoreleasing all the types we pass to the enumerator (which could be numerous), we'll just hold onto these arrays.
    NSMutableArray *systemTypes = [[NSMutableArray alloc] init];
    NSMutableArray *thirdPartyTypes = [[NSMutableArray alloc] init];
    
    for (NSString *type in allTypes) {
        BOOL isSystemBundle = NO;
        
        NSURL *bundleURL = CFBridgingRelease(UTTypeCopyDeclaringBundleURL((__bridge CFStringRef)type));
        if (bundleURL) {
            NSString *declaringBundleIdentifier = [[NSBundle bundleWithURL:bundleURL] bundleIdentifier];
            isSystemBundle = [declaringBundleIdentifier isEqualToString:SYSTEM_TYPE_BUNDLE_IDENTIFIER];
        }
                
        if (isSystemBundle)
            [systemTypes addObject:type];
        else
            [thirdPartyTypes addObject:type];
    }
    
    OB_FOR_ALL(array, systemTypes, thirdPartyTypes) {
        [array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop){
            enumerator(obj, &stopEnumerating);
            if (stopEnumerating)
                *stop = YES;
        }];
        
        if (stopEnumerating)
            break;
    }
    
    [systemTypes release];
    [thirdPartyTypes release];
}

// This hides a bunch of __bridge usages and shortens up code checking for multiple types. We could explicitly list the first type to start and use it as the va_start() argument, but then we'd need to check it specifically.
BOOL _OFTypeConformsToOneOfTypes(NSString *type, ...)
{
    va_list args;
    va_start(args, type);

    BOOL conforms = NO;
    NSString *checkType;
    while ((checkType = va_arg(args, NSString *))) {
        if (UTTypeConformsTo((OB_BRIDGE CFStringRef)type, (OB_BRIDGE CFStringRef)checkType)) {
            conforms = YES;
            break;
        }
    }

    va_end(args);
    return conforms;
}

