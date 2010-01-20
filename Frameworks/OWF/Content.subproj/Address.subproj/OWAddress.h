// Copyright 1997-2006, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <OWF/OWContentCacheProtocols.h>
#import <OWF/OWProcessor.h> // For the OWProcessorContext protocol
#import <OWF/FrameworkDefines.h>

@class NSArray, NSBundle, NSCharacterSet, NSData, NSMutableCharacterSet, NSScanner, NSURL, NSURLRequest;
@class OWContentType, OWPipeline, OWURL;

typedef enum {
    OWAddressEffectFollowInWindow, // display in the same window
    OWAddressEffectNewBrowserWindow, // display in a new browser window
    OWAddressEffectOpenBookmarksWindow, // display in a bookmarks window
} OWAddressEffect;

@interface OWAddress : OFObject <OWConcreteCacheEntry, NSCopying>
{
    OWURL *url;
    NSString *target;
    NSString *methodString;
    NSDictionary *methodDictionary;
    struct {
        unsigned int effect:3;
        unsigned int forceAlwaysUnique:1;
    } flags;
    
    // Cached information
    NSString *cacheKey;
    
    // Bonus extra information, use it any way you wish
    NSDictionary *contextDictionary;
}

+ (NSDictionary *)shortcutDictionary;
+ (void)setShortcutDictionary:(NSDictionary *)newShortcutDictionary;
+ (void)reloadShortcutDictionaryFromDefaults;
+ (void)reloadAddressFilterArrayFromDefaults;
+ (void)addAddressToWhitelist:(OWAddress *)anAddress;
+ (void)addAddressToBlacklist:(OWAddress *)anAddress;

+ (OWAddress *)addressWithURL:(OWURL *)aURL target:(NSString *)aTarget methodString:(NSString *)aMethodString methodDictionary:(NSDictionary *)aMethodDictionary effect:(OWAddressEffect)anEffect forceAlwaysUnique:(BOOL)shouldForceAlwaysUnique contextDictionary:(NSDictionary *)contextDictionary;
+ (OWAddress *)addressWithURL:(OWURL *)aURL target:(NSString *)aTarget methodString:(NSString *)aMethodString methodDictionary:(NSDictionary *)aMethodDictionary effect:(OWAddressEffect)anEffect forceAlwaysUnique:(BOOL)shouldForceAlwaysUnique;
+ (OWAddress *)addressWithURL:(OWURL *)aURL target:(NSString *)aTarget effect:(OWAddressEffect)anEffect;
+ (OWAddress *)addressWithURL:(OWURL *)aURL;
+ (OWAddress *)addressForString:(NSString *)anAddressString;
+ (OWAddress *)addressForDirtyString:(NSString *)anAddressString;
+ (OWAddress *)addressWithFilename:(NSString *)filename;

+ (OWAddress *)addressFromNSURL:(NSURL *)nsURL;

+ (NSString *)stringForEffect:(OWAddressEffect)anEffect;
+ (OWAddressEffect)effectForString:(NSString *)anEffectString;

- initWithURL:(OWURL *)aURL target:(NSString *)aTarget methodString:(NSString *)aMethodString methodDictionary:(NSDictionary *)aMethodDictionary effect:(OWAddressEffect)anEffect forceAlwaysUnique:(BOOL)shouldForceAlwaysUnique contextDictionary:(NSDictionary *)contextDictionary;
- initWithURL:(OWURL *)aURL target:(NSString *)aTarget methodString:(NSString *)aMethodString methodDictionary:(NSDictionary *)aMethodDictionary effect:(OWAddressEffect)anEffect forceAlwaysUnique:(BOOL)shouldForceAlwaysUnique;
- initWithURL:(OWURL *)aURL target:(NSString *)aTarget effect:(OWAddressEffect)anEffect;
- initWithURL:(OWURL *)aURL;

- initWithArchiveDictionary:(NSDictionary *)dictionary;

// Attributes

- (OWURL *)url;
- (OWURL *)proxyURL;
- (NSString *)methodString;
- (NSDictionary *)methodDictionary;
- (NSString *)target;
- (NSString *)localFilename;
- (NSString *)addressString;
- (BOOL)representsFile;
- (NSDictionary *)contextDictionary;
- (OWContentType *)probableContentTypeBasedOnPath;

// Displaying an address

- (NSString *)drawLabel;
- (BOOL)isVisited;
- (BOOL)isSecure;
- (NSString *)bestKnownTitle;
- (NSString *)bestKnownTitleWithFragment; // includes the part of the URL after # in parenthesis

// Exactly the same address

- (BOOL)isEqual:(id)anObject;

- (BOOL)isAlwaysUnique;
- (NSString *)cacheKey;

// Not the same address, but will fetch the same data (same except fragment)

- (BOOL)isSameDocumentAsAddress:(OWAddress *)otherAddress;

// What happens when you open this address

- (OWAddressEffect)effect;
- (NSString *)effectString;

- (NSDictionary *)archiveDictionary;

// Related addresses

- (OWAddress *)addressForRelativeString:(NSString *)relativeAddressString;
- (OWAddress *)addressForRelativeString:(NSString *)relativeAddressString target:(NSString *)aTarget effect:(OWAddressEffect)anEffect;
- (OWAddress *)addressForRelativeString:(NSString *)relativeAddressString inProcessorContext:(id <OWProcessorContext>)pipeline target:(NSString *)aTarget effect:(OWAddressEffect)anEffect;

- (OWAddress *)addressForDirtyRelativeString:(NSString *)relativeAddressString;

- (OWAddress *)addressWithGetQuery:(NSString *)query;
- (OWAddress *)addressWithPath:(NSString *)aPath;
- (OWAddress *)addressWithMethodString:(NSString *)newMethodString;
- (OWAddress *)addressWithMethodString:(NSString *)newMethodString methodDictionary:(NSDictionary *)newMethodDictionary forceAlwaysUnique:(BOOL)shouldForceAlwaysUnique;
- (OWAddress *)addressWithTarget:(NSString *)aTarget;
- (OWAddress *)addressWithEffect:(OWAddressEffect)newEffect;
- (OWAddress *)addressWithForceAlwaysUnique:(BOOL)shouldForceAlwaysUnique;
- (OWAddress *)createUniqueVersionOfAddress;
- (OWAddress *)addressWithoutFragment;

- (OWAddress *)addressWithContextDictionary:(NSDictionary *)newContextDictionary;
- (OWAddress *)addressWithContextObject:object forKey:(NSString *)key;

//
- (NSString *)suggestedFilename;
- (NSString *)suggestedFileType;

// Checks whether the address would be filtered by the adblocking preferences (does not check whether the adblocking preferences are enabled in this situation)
- (BOOL)isFiltered;
- (BOOL)isWhitelisted;

// Type conversions
- (NSURL *)NSURL;
- (NSURLRequest *)NSURLRequest;

@end


OWF_EXTERN NSString *OWAddressContentDataMethodKey;
OWF_EXTERN NSString *OWAddressContentAdditionalHeadersMethodKey;
OWF_EXTERN NSString *OWAddressContentStringMethodKey;
OWF_EXTERN NSString *OWAddressContentTypeMethodKey;  // Indicates the content-type of the method data (POST/PUT body, e.g.)
OWF_EXTERN NSString *OWAddressBoundaryMethodKey;

OWF_EXTERN NSString *OWAddressContentTypeContextKey;  // Hack to indicate the type of the returned object, if already known; only works in certain cases
OWF_EXTERN NSString *OWAddressSourceRangeContextKey;

OWF_EXTERN NSString *OWAddressesToFilterDefaultName;
OWF_EXTERN NSString *OWAddressesToAllowDefaultName;
OWF_EXTERN NSString *OWAddressFilteringEnabledDefaultName;

OWF_EXTERN NSString *OWAddressShortcutsDidChange;
