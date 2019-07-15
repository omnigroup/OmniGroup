// Copyright 2011-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/macros.h>
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#endif

NS_ASSUME_NONNULL_BEGIN

// ARC doesn't like casting a CFStringRef to CFStringRef with __bridge. Use this overloadable function to allow passing CFStringRef or NSString * to these helpers.
static inline CFStringRef __attribute__((overloadable)) _OFAsCFString(CFStringRef str) { return str; }
static inline CFStringRef __attribute__((overloadable)) _OFAsCFString(NSString *str) { return (OB_BRIDGE CFStringRef)str; }
static inline NSString * __attribute__((overloadable)) _OFAsNSString(CFStringRef str) { return (OB_BRIDGE NSString *)str; }
static inline NSString * __attribute__((overloadable)) _OFAsNSString(NSString *str) { return str; }

// A path extension that denotes something that is definitely a folder and not a package. This allows OmniPresence iOS clients to make folders with dots in the name w/o worrying whether the thing after the last dot might be a path extension for some file format unknown to that app at that time (though OmniPresence does communitate package types to the iOS clients). This is the same path extension that iWork for iOS uses in its iCloud folder support, so it should be relatively safe to assume that some one won't come along and write an app that claims it is a package. Even so, we'll do our best to always treat things with this path extension as plain folders.
extern NSString * const OFDirectoryPathExtension;

// Returns a uniform type identifier for a filesystem URL based on its extension. This is intended to be a replacement for -[NSURL getResourceValue: forKey:(NSURLTypeIdentifierKey) error:]. The URL must point to an existing file in the filesystem, or else this function will return nil and populate the variable pointed to by outError (if non-NULL) with an NSError object explaining why. If multiple identifiers are defined for the same extension, this function prefers types that are registered by the running exceutable's main bundle.
extern NSString * _Nullable OFUTIForFileURLPreferringNative(NSURL *fileURL, NSError **outError);

// Returns a uniform type identifier for files or directories with the given extension. If multiple identifiers are defined for the same extension, this function prefers types that are registered by the running executable's main bundle.
// Optionally, you can pass an NSNumber with a boolValue=YES to restrict the search to types which conform to public.directory (directories and document packages), or NO to restrict the search to types which conform to public.data (flat files and other byte streams). If you don't know or care whether the extension refers to a flat file or directory, pass nil for this arugment.
extern NSString *OFUTIForFileExtensionPreferringNative(NSString *extension, NSNumber * _Nullable isDirectory);

// Returns a uniform type identifier for the given tag class and value. If multiple identifiers are defined for the same tag value, this function prefers types that are registered by the running executable's main bundle. Optionally, returned types can be restricted to those conforming to the identifier named by the conformingToUTIOrNull parameter.
extern NSString *OFUTIForTagPreferringNative(CFStringRef tagClass, NSString *tag, CFStringRef _Nullable conformingToUTIOrNull);

extern NSString * _Nullable OFUTIPreferredTagWithClass(NSString *fileType, CFStringRef tag);
extern NSString * _Nullable OFUTIDescription(NSString *fileType);

// Returns a file extension for a given uniform type identifier.  This function prefers prefers types that are registered by the running exceutable's main bundle
extern NSString * _Nullable OFPreferredFilenameExtensionForTypePreferringNative(NSString *fileType);

// Hide the bridging and return an autoreleased NSString
#define OFPreferredPathExtensionForUTI(uti) ((NSString *)CFBridgingRelease(UTTypeCopyPreferredTagWithClass(_OFAsCFString(uti), kUTTagClassFilenameExtension)))


// Enumerates all known uniform type identifiers that match the provided tag. Native types (types defined in the main bundle's Info.plist) are enumerated first--exported types before imported types--followed by types declared by the system, and finally types defined by third-party bundles. Optionally, enumeration can be restricted to those types conforming to the identifier named by the conformingToUTIOrNil parameter.
typedef void (^OFUTIEnumerator)(NSString *typeIdentifier, BOOL *stop);
extern void OFUTIEnumerateKnownTypesForTagPreferringNative(NSString *tagClass, NSString *tagValue, NSString * _Nullable conformingToUTIOrNil, OFUTIEnumerator enumerator);

#define OFTypeConformsTo(type, conformsToType) UTTypeConformsTo(_OFAsCFString(type), _OFAsCFString(conformsToType))
#define OFTypeEqual(type, otherType) UTTypeEqual(_OFAsCFString(type), _OFAsCFString(otherType))

extern BOOL _OFTypeConformsToOneOfTypes(NSString *type, ...) NS_REQUIRES_NIL_TERMINATION;
#define OFTypeConformsToOneOfTypes(type, ...) _OFTypeConformsToOneOfTypes(_OFAsNSString(type), ## __VA_ARGS__)
extern BOOL OFTypeConformsToOneOfTypesInArray(NSString * _Nullable type, NSArray<NSString *> *types);

NS_ASSUME_NONNULL_END
