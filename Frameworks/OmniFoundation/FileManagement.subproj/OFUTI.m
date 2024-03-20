// Copyright 2011-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFUTI.h>

@import UniformTypeIdentifiers;

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/OFController.h>
#endif

NSString * const OFDirectoryPathExtension = @"folder";
NSString * const OFExportOnlyDeclaration = @"OFExportOnlyDeclaration";
NSString * const OFTUTIDeclarationUsageType = @"OFTUTIDeclarationUsageType";

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
static NSDictionary *ExportedTypeDeclarationsByTag;
static NSDictionary *ImportedTypeDeclarationsByTag;
static NSDictionary *ExportedTypeDefinitionByFileType;
static NSDictionary *ImportedTypeDefinitionByFileType;

// A mapping of the type definitions that we've found
static NSDictionary <NSString *, NSDictionary *> *TypeDefinitionByIdentifier;

static BOOL OFUTIDiagnosticsEmitted = NO;

static BOOL _TypeConformsToType(NSString * _Nonnull identifier, NSString * _Nonnull conformanceCheckIdentifier)
{
    if (@available(macOS 11, *)) {
        UTType *type = [UTType typeWithIdentifier:identifier];
        UTType *conformanceType = [UTType typeWithIdentifier:conformanceCheckIdentifier];
        OBASSERT(type != nil);
        OBASSERT(conformanceType != nil);
        return conformanceType != nil && [type conformsToType:conformanceType];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return UTTypeConformsTo((__bridge CFStringRef)identifier, (__bridge CFStringRef)conformanceCheckIdentifier);
#pragma clang diagnostic pop
    }
}

#define OFUTI_DIAG(fmt, ...) \
    do { \
        NSLog(@"OFUTI: " fmt, __VA_ARGS__); \
        OFUTIDiagnosticsEmitted = YES; \
    } while (0)

// Returns a +1 retained NSDictionary transformation of the provided array of type declarations (kUT{Exported,Imported}TypeDeclarationsKey) into the form described above.
static NSDictionary *CreateTagDictionaryFromTypeDeclarations(NSArray *typeDeclarations, NSString *declarationType)
{
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *definitions = [[NSMutableDictionary alloc] init];
    
    if ([declarationType isEqualToString:(NSString *)kUTExportedTypeDeclarationsKey]) {
        if (ExportedTypeDefinitionByFileType) {
            [definitions addEntriesFromDictionary:ExportedTypeDefinitionByFileType];
            [ExportedTypeDefinitionByFileType release];
        }
        ExportedTypeDefinitionByFileType = definitions;
    } else if ([declarationType isEqualToString:(NSString *)kUTImportedTypeDeclarationsKey]) {
        if (ImportedTypeDefinitionByFileType) {
            [definitions addEntriesFromDictionary:ImportedTypeDefinitionByFileType];
            [ImportedTypeDefinitionByFileType release];
        }
        ImportedTypeDefinitionByFileType = definitions;
    } else {
        [definitions release];
        definitions = nil;
    }

    // A type declaration is a dictionary...
    for (NSDictionary *declaration in typeDeclarations) {
        // ...with a string value for kUTTypeIdentifierKey...
        NSString *identifier = declaration[(NSString *)kUTTypeIdentifierKey];
        if (![identifier isKindOfClass:[NSString class]]) {
            OFUTI_DIAG(@"Type declaration identifier must be a string; found \"%@\" instead.", identifier);
            continue;
        }

        // TODO: Warn about this instead of silently 'fixing' it.
        identifier = [identifier lowercaseString];

        // register the definition
        [definitions setObject:declaration forKey:identifier];

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
                    BOOL conformsToPublicData;
                    BOOL conformsToPublicDirectory;
                    if (@available(macOS 11, *)) {
                        UTType *identifierType = [UTType typeWithIdentifier:identifier];
                        conformsToPublicData = [identifierType conformsToType:UTTypeData];
                        conformsToPublicDirectory = [identifierType conformsToType:UTTypeDirectory];
                        
                        if (!conformsToPublicData && !conformsToPublicDirectory) {
                            OFUTI_DIAG(@"Type declaration for type \"%@\" does not conform to either \"%@\" or \"%@\"; it should conform to exactly one. Declaration is %@", identifier, UTTypeData.identifier, UTTypeDirectory.identifier, declaration);
                        } else if (conformsToPublicData && conformsToPublicDirectory) {
                            OFUTI_DIAG(@"Type declaration for type \"%@\" conforms to both \"%@\" and \"%@\"; it should conform to exactly one. Declaration is %@", identifier, UTTypeData.identifier, UTTypeDirectory.identifier, declaration);
                        }

                    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                        conformsToPublicData = _TypeConformsToType(identifier, (__bridge NSString *)kUTTypeData);
                        conformsToPublicDirectory = _TypeConformsToType(identifier, (__bridge NSString *)kUTTypeDirectory);
                        
                        if (!conformsToPublicData && !conformsToPublicDirectory) {
                            OFUTI_DIAG(@"Type declaration for type \"%@\" does not conform to either \"%@\" or \"%@\"; it should conform to exactly one. Declaration is %@", identifier, (NSString *)kUTTypeData, (NSString *)kUTTypeDirectory, declaration);
                        } else if (conformsToPublicData && conformsToPublicDirectory) {
                            OFUTI_DIAG(@"Type declaration for type \"%@\" conforms to both \"%@\" and \"%@\"; it should conform to exactly one. Declaration is %@", identifier, (NSString *)kUTTypeData, (NSString *)kUTTypeDirectory, declaration);
                        }
#pragma clang diagnostic pop
                    }
                    // This allows an Application to define a specific UTI for export only which is not declared in UTExportedTypeDeclarations.  This allows an application to register multiple UTIs for say HTML, without generating an error.
                    NSString *declarationUsageType = [declaration objectForKey:OFTUTIDeclarationUsageType];
                    if ([declarationType isEqualToString:(NSString *)kUTImportedTypeDeclarationsKey] && ![NSString isEmptyString:declarationUsageType] && [declarationUsageType isEqualToString:OFExportOnlyDeclaration]) {
                        conformsToPublicData = NO;
                        conformsToPublicDirectory = NO;
                    }

                    // Enumerate the existing types declared for this tag and warn if they share the same conformance to the flat-file (public.data) or directory (public.directory) physical type trees.
                    for (NSString *existingIdentifier in mappedIdentifiers) {
                        BOOL existingIDConformsToData;
                        BOOL existingIDConformsToDirectory;
                        if (@available(macOS 11, *)) {
                            UTType *existingIdentifierType = [UTType typeWithIdentifier:existingIdentifier];
                            existingIDConformsToData = [existingIdentifierType conformsToType:UTTypeData];
                            existingIDConformsToDirectory = [existingIdentifierType conformsToType:UTTypeDirectory];
                        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                            existingIDConformsToData = _TypeConformsToType(existingIdentifier, (__bridge NSString *)kUTTypeData);
                            existingIDConformsToDirectory = _TypeConformsToType(existingIdentifier, (__bridge NSString *)kUTTypeDirectory);
#pragma clang diagnostic pop
                        }
                        if ((conformsToPublicData && existingIDConformsToData)
                            || (conformsToPublicDirectory && existingIDConformsToDirectory)) {
                            OFUTI_DIAG(@"Conflict detected registering type \"%@\": type \"%@\" has already claimed tag \"%@\" for class \"%@\". Which one is used is undefined.", identifier, existingIdentifier, value, tagClass);
                            OFUTI_DIAG(@"If these types are for export only, consider using the %@ key with value %@ in the type definition in your Info.plist to silence this warning.", OFTUTIDeclarationUsageType, OFExportOnlyDeclaration);
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

static void AddTypeDefinitions(NSMutableDictionary <NSString *, NSDictionary *> *typeDefinitionByIdentifier, NSArray <NSDictionary *> *typeDefinitions)
{
    for (NSDictionary *typeDefinition in typeDefinitions) {
        NSString *identifier = typeDefinition[(NSString *)kUTTypeIdentifierKey];
        if (!identifier) {
            OBASSERT_NOT_REACHED("Type definition doesn't contain an identifier: %@", typeDefinition);
            continue;
        }

        OBASSERT(typeDefinitionByIdentifier[identifier] == nil);
        typeDefinitionByIdentifier[identifier] = typeDefinition;
    }
}

static void InitializeKnownTypeDictionaries(void)
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

        NSArray <NSDictionary *> *exportedTypeDeclarations = infoDictionary[(NSString *)kUTExportedTypeDeclarationsKey];
        NSArray <NSDictionary *> *importedTypeDeclarations = infoDictionary[(NSString *)kUTImportedTypeDeclarationsKey];

        // Keep a record of all the imported and exported type definitions. LaunchServices only pays attention to the app bundle, but we want to emulate some queries for xctest bundles.
        {
            NSMutableDictionary <NSString *, NSDictionary *> *typeDefinitionByIdentifier = [NSMutableDictionary dictionary];
            AddTypeDefinitions(typeDefinitionByIdentifier, exportedTypeDeclarations);
            AddTypeDefinitions(typeDefinitionByIdentifier, importedTypeDeclarations);
            TypeDefinitionByIdentifier = [typeDefinitionByIdentifier copy];

            // Warn if we have a type definition that says it conforms to another type for which we can't find a definition.
#ifdef OMNI_ASSERTIONS_ON
            [TypeDefinitionByIdentifier enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, NSDictionary *typeDefinition, BOOL * _Nonnull stop) {
                id conformsToValue = typeDefinition[(__bridge NSString *)kUTTypeConformsToKey];
                if (!conformsToValue) {
                    return;
                }
                if (![conformsToValue isKindOfClass:[NSArray class]]) {
                    conformsToValue = @[conformsToValue];
                }

                for (NSString *conformsToType in conformsToValue) {
                    OBASSERT([conformsToType isKindOfClass:[NSString class]]);

                    if (typeDefinitionByIdentifier[conformsToType]) {
                        // This is a type we know about via our plist entries
                        return;
                    }

                    NSDictionary *conformedDefinition;
                    if (@available(macOS 11, *)) {
                        UTType *conformsToUTType = [UTType typeWithIdentifier:conformsToType];
                        OBASSERT(conformsToUTType != nil, "Type %@ is declared to conform to %@, which cannot be found.", identifier, conformsToType);
                    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    conformedDefinition = CFBridgingRelease(UTTypeCopyDeclaration((__bridge CFStringRef)conformsToType));
#pragma clang diagnostic pop
                    OBASSERT(conformedDefinition != nil, "Type %@ is declared to conform to %@, which cannot be found.", identifier, conformsToType);
                    }
                }
            }];
#endif
        }

        ExportedTypeDeclarationsByTag = CreateTagDictionaryFromTypeDeclarations(exportedTypeDeclarations, (NSString *)kUTExportedTypeDeclarationsKey);
        ImportedTypeDeclarationsByTag = CreateTagDictionaryFromTypeDeclarations(importedTypeDeclarations, (NSString *)kUTImportedTypeDeclarationsKey);
        
        // Warn if both the exported and imported type dictionaries both declared types for the same tag.
        NSArray *allTagClasses = [[ExportedTypeDeclarationsByTag allKeys] arrayByAddingObjectsFromArray:[ImportedTypeDeclarationsByTag allKeys]];
        for (NSString *tagClass in allTagClasses) {
            NSDictionary *exportedClassDict = [ExportedTypeDeclarationsByTag objectForKey:tagClass];
            NSDictionary *importedClassDict = [ImportedTypeDeclarationsByTag objectForKey:tagClass];
            
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
    BOOL isFilenameExtension;
    if (@available(macOS 11, *)) {
        isFilenameExtension = OFISEQUAL(tagClass, UTTagClassFilenameExtension);
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        isFilenameExtension = OFISEQUAL(tagClass, (NSString *)kUTTagClassFilenameExtension);
#pragma clang diagnostic pop
    }
    if (mappedIdentifiers == nil && isFilenameExtension) {
        // File extensions should be case-insensitive
        mappedIdentifiers = [classDict objectForKey:[tagValue lowercaseString]];
    }
    
    for (NSString *identifier in mappedIdentifiers) {
        enumerator(identifier, &stopEnumerating);
        if (stopEnumerating)
            return;
    }
}

#pragma mark - Public API

NSString * _Nullable OFUTIForFileURLPreferringNative(NSURL *fileURL, NSError **outError)
{
    if (![fileURL isFileURL])
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Argument to OFUTIForFileURL must be a file URL, not %@", [fileURL absoluteString]] userInfo:nil];
    
    __autoreleasing NSNumber *isDirectoryValue = nil;
    if (![fileURL getResourceValue:&isDirectoryValue forKey:NSURLIsDirectoryKey error:outError]) {
        return nil;
    }

    return OFUTIForFileExtensionPreferringNative([fileURL pathExtension], isDirectoryValue);
}

NSString *OFUTIForFileExtensionPreferringNative(NSString *extension, NSNumber * _Nullable isDirectory)
{
    NSString *folderTypeIdentifier;
    CFStringRef directoryTypeIdentifier;
    CFStringRef dataTypeIdentifier;
    CFStringRef tagClassFilenameExtension;
    if (@available(macOS 11, *)) {
        folderTypeIdentifier = UTTypeFolder.identifier;
        directoryTypeIdentifier = (__bridge CFStringRef)(UTTypeDirectory.identifier);
        dataTypeIdentifier = (__bridge CFStringRef)(UTTypeData.identifier);
        tagClassFilenameExtension = (__bridge CFStringRef)UTTagClassFilenameExtension;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        folderTypeIdentifier = (OB_BRIDGE NSString *)kUTTypeFolder;
        directoryTypeIdentifier = kUTTypeDirectory;
        dataTypeIdentifier = kUTTypeData;
        tagClassFilenameExtension = kUTTagClassFilenameExtension;
#pragma clang diagnostic pop
    }
    if (isDirectory && ([extension isEqualToString:OFDirectoryPathExtension] || extension.length == 0)) {
        OBASSERT([isDirectory boolValue]); // if we have no extension, or it's a path extension, we should be a folder.
        return folderTypeIdentifier;
    }
    
    CFStringRef conformingUTI = NULL;
    if (isDirectory && [isDirectory boolValue]) {
        if (OFIsEmptyString(extension)) {
            return (__bridge NSString *)directoryTypeIdentifier; // Just some plain directory
        }
        conformingUTI = directoryTypeIdentifier;
    } else if (isDirectory && !([isDirectory boolValue])) {
        conformingUTI = dataTypeIdentifier;
    }
    
    return OFUTIForTagPreferringNative(tagClassFilenameExtension, extension, conformingUTI);
}

NSString *OFUTIForTagPreferringNative(CFStringRef tagClass, NSString *tagValue, CFStringRef _Nullable conformingToUTIOrNull)
{
    __block NSString *resolvedType = nil;
    
    OFUTIEnumerateKnownTypesForTagPreferringNative((__bridge NSString *)tagClass, tagValue, (__bridge NSString *)conformingToUTIOrNull, ^(NSString *typeIdentifier, BOOL *stop) {
        resolvedType = typeIdentifier;
        *stop = YES;
    });
    
    OBASSERT_NOTNULL(resolvedType, "No resolved type for class %@, value %@, conforming to %@", tagClass, tagValue, conformingToUTIOrNull); // should have at least gotten a dynamic type
    return resolvedType;
}

// This cleans up some Swift bridging oddities with Unmanaged<CFString>? results.
NSString * _Nullable OFUTIPreferredTagWithClass(NSString *fileType, CFStringRef tag)
{
    if (@available(macOS 11, *)) {
        return [[[[UTType typeWithIdentifier:fileType] tags] valueForKey:(NSString *)tag] firstObject];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)fileType, tag));
#pragma clang diagnostic pop
    }
}

NSArray <NSString *> *_Nullable OFUTIPathExtensions(NSString *fileType)
{
    if (@available(macOS 11, *)) {
        // there's a specific UTType preferred fileExtension api, which probably should be used...
        return [[[UTType typeWithIdentifier:fileType] tags] valueForKey: UTTagClassFilenameExtension];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return CFBridgingRelease(UTTypeCopyAllTagsWithClass((__bridge CFStringRef)fileType, kUTTagClassFilenameExtension));
#pragma clang diagnostic pop
    }
}

NSString * _Nullable OFUTIDescription(NSString *fileType)
{
    if (@available(macOS 11, *)) {
        return [[UTType typeWithIdentifier:fileType] description];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return CFBridgingRelease(UTTypeCopyDescription((__bridge CFStringRef)fileType));
#pragma clang diagnostic pop
    }
}

static NSString * _Nullable _OFGetFileExtensionFromDefinitionsForType(NSDictionary *definitions, NSString *fileType)
{
    NSDictionary *definition = [definitions objectForKey:fileType];

    if (definition) {
        NSDictionary *tagSpecs = [definition objectForKey:(NSString *)kUTTypeTagSpecificationKey];
        id values;
        if (@available(macOS 11, *)) {
            values = [[[UTType typeWithIdentifier:fileType] tags] valueForKey: UTTagClassFilenameExtension];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            values = [tagSpecs objectForKey:(NSString *)kUTTagClassFilenameExtension];
#pragma clang diagnostic pop
        }
        if (values) {
            if ([values isKindOfClass:NSArray.class]) {
                return [(NSArray *)values firstObject];
            } else if ([values isKindOfClass:NSString.class]) {
                return (NSString *)values;
            }
        } else {
            return nil;
        }
    }
    return nil;
}

NSString * _Nullable OFPreferredFilenameExtensionForTypePreferringNative(NSString *fileType)
{
    // Check or own database
    NSString *fileExtension = _OFGetFileExtensionFromDefinitionsForType(ExportedTypeDefinitionByFileType, fileType);

    if (!fileExtension) {
        fileExtension = _OFGetFileExtensionFromDefinitionsForType(ImportedTypeDefinitionByFileType, fileType);
    }

    if (!fileExtension) {
        if (@available(macOS 11, *)) {
            fileExtension = [[UTType typeWithIdentifier:fileType] preferredFilenameExtension];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            fileExtension = [((NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)fileType, kUTTagClassFilenameExtension)) autorelease];
#pragma clang diagnostic pop
        }
    }

    return fileExtension;
}

void OFUTIEnumerateKnownTypesForTagPreferringNative(NSString *tagClass, NSString *tagValue, NSString *conformingToUTIOrNil, OFUTIEnumerator enumerator)
{
    __block BOOL stopEnumerating = NO;
    
    // Check our Info.plist first, preferring exported types over imported ones.
    InitializeKnownTypeDictionaries();
    
    OB_FOR_ALL(dict, ExportedTypeDeclarationsByTag, ImportedTypeDeclarationsByTag) {
        EnumerateIdentifiersForTagInDictionary(dict, tagClass, tagValue, ^(NSString *typeIdentifier, BOOL *stop) {
            if (!conformingToUTIOrNil || _TypeConformsToType(typeIdentifier, conformingToUTIOrNil)) {
                enumerator(typeIdentifier, &stopEnumerating);
                if (stopEnumerating)
                    *stop = YES;
            }
        });
        
        if (stopEnumerating)
            return;
    }
    
    // No luck looking in our own Info.plist. Look through all the definitions Launch Services knows about, but prefer any declarations by CoreServices. We allow the caller to pass a conformingToUTI hint in order to limit the size of and time spent copying this array.
    NSArray *allTypes;
    
    if (@available(macOS 11, *)) {
        UTType *conformanceType = conformingToUTIOrNil ? [UTType typeWithIdentifier: conformingToUTIOrNil] : nil;
        NSArray<UTType *> *allUTTypes = [UTType typesWithTag:tagValue tagClass:tagClass conformingToType:conformanceType];
        allTypes = [allUTTypes arrayByPerformingBlock:^NSString * (UTType * _Nonnull uttype) {
            return uttype.identifier;
        }];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        allTypes = CFBridgingRelease(UTTypeCreateAllIdentifiersForTag((__bridge CFStringRef)tagClass, (__bridge CFStringRef)tagValue, (__bridge CFStringRef)conformingToUTIOrNil));
#pragma clang diagnostic pop
    }

    if (!allTypes)
        return;
    
    // These arrays might hold the last remaining retain on the type identifiers we passed to the enumerator block. Rather than retain/autoreleasing all the types we pass to the enumerator (which could be numerous), we'll just hold onto these arrays.
    NSMutableArray *systemTypes = [[NSMutableArray alloc] init];
    NSMutableArray *thirdPartyTypes = [[NSMutableArray alloc] init];
    
    for (NSString *type in allTypes) {
        BOOL isSystemBundle = NO;
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSURL *bundleURL = CFBridgingRelease(UTTypeCopyDeclaringBundleURL((__bridge CFStringRef)type)); // there's not a new non-deprecated API that does this, as far as I can find.
#pragma clang diagnostic pop

        if (bundleURL) {
            NSString *declaringBundleIdentifier = [[NSBundle bundleWithURL:bundleURL] bundleIdentifier];
            isSystemBundle = [declaringBundleIdentifier hasPrefix:@"com.apple."];
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
    if (type == nil) {
        return NO;
    }
    va_list args;
    va_start(args, type);

    BOOL conforms = NO;
    NSString *checkType;
    while ((checkType = va_arg(args, NSString *))) {
        if (_TypeConformsToType(type, checkType)) {
            conforms = YES;
            break;
        }
    }

    va_end(args);
    return conforms;
}

BOOL OFTypeConformsToOneOfTypesInArray(NSString *type, NSArray<NSString *> *types)
{
    if (type == nil) {
        return NO;
    }
    if ([types containsObject:type]) {
        return YES; // Avoid eventually calling UTTypeConformsTo when possible.
    }
    for (NSString *checkType in types) {
        if (_TypeConformsToType(type, checkType)) {
            return YES;
        }
    }
    return NO;
}
