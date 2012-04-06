// Copyright 2011-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

// Returns a uniform type identifier for a filesystem URL based on its extension. This is intended to be a replacement for -[NSURL getResourceValue: forKey:(NSURLTypeIdentifierKey) error:]. The URL must point to an existing file in the filesystem, or else this function will return nil and populate the variable pointed to by outError (if non-NULL) with an NSError object explaining why. If multiple identifiers are defined for the same extension, this function prefers types that are registered by the running exceutable's main bundle.
extern NSString *OFUTIForFileURLPreferringNative(NSURL *fileURL, NSError **outError);

// Returns a uniform type identifier for files or directories with the given extension. If multiple identifiers are defined for the same extension, this function prefers types that are registered by the running executable's main bundle.
// Optionally, you can pass an NSNumber with a boolValue=YES to restrict the search to types which conform to public.directory (directories and document packages), or NO to restrict the search to types which conform to public.data (flat files and other byte streams). If you don't know or care whether the extension refers to a flat file or directory, pass nil for this arugment.
extern NSString *OFUTIForFileExtensionPreferringNative(NSString *extension, NSNumber *isDirectory);

// Returns a uniform type identifier for the given tag class and value. If multiple identifiers are defined for the same tag value, this function prefers types that are registered by the running executable's main bundle. Optionally, returned types can be restricted to those conforming to the identifier named by the conformingToUTIOrNull parameter.
extern NSString *OFUTIForTagPreferringNative(CFStringRef tagClass, NSString *tag, CFStringRef conformingToUTIOrNull);

// Enumerates all known uniform type identifiers that match the provided tag. Native types (types defined in the main bundle's Info.plist) are enumerated first--exported types before imported types--followed by types declared by the system, and finally types defined by third-party bundles. Optionally, enumeration can be restricted to those types conforming to the identifier named by the conformingToUTIOrNil parameter.
typedef void (^OFUTIEnumerator)(NSString *typeIdentifier, BOOL *stop);
extern void OFUTIEnumerateKnownTypesForTagPreferringNative(NSString *tagClass, NSString *tagValue, NSString *conformingToUTIOrNil, OFUTIEnumerator enumerator);
