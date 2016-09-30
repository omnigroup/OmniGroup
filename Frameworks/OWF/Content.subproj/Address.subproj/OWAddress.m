// Copyright 1999-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWAddress.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContentCacheProtocols.h>
#import <OWF/OWContentInfo.h>
#import <OWF/OWContentType.h>
#import <OWF/OWContentTypeLink.h>
#import <OWF/OWConversionPathElement.h>
#import <OWF/OWDocumentTitle.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWProcessorDescription.h>
#import <OWF/OWProxyServer.h>
#import <OWF/OWSitePreference.h>
#import <OWF/OWUnknownDataStreamProcessor.h>
#import <OWF/OWURL.h>

RCS_ID("$Id$")

NSString * const OWAddressContentDataMethodKey = @"Content-Data";
NSString * const OWAddressContentAdditionalHeadersMethodKey = @"Additional-Headers";
NSString * const OWAddressContentStringMethodKey = @"Content-String";
NSString * const OWAddressContentTypeMethodKey = @"Content-Type";
NSString * const OWAddressBoundaryMethodKey = @"Boundary";

NSString * const OWAddressContentTypeContextKey = @"Content-Type";
NSString * const OWAddressSourceRangeContextKey = @"Range";

NSString * const OWAddressesToFilterDefaultName = @"OWAddressesToFilter";
NSString * const OWAddressesToAllowDefaultName = @"OWAddressesToAllow";
NSString * const OWAddressFilteringEnabledDefaultName = @"OWAddressFilteringEnabled";
NSString * const OWAddressShortcutsDidChange = @"OWAddressShortcutsDidChange";

static NSDictionary *_shortcutDictionary = nil;
static NSLock *_filterRegularExpressionLock = nil;
static NSRegularExpression *_filterRegularExpression = nil;
static NSRegularExpression *_whitelistFilterRegularExpression = nil;
static NSCharacterSet *nonShortcutCharacterSet;
static unsigned int uniqueKeyCount;
static NSLock *uniqueKeyCountLock;
static NSMutableDictionary *lowercaseEffectNameDictionary;

static OFPreference *directoryIndexFilenamePreference = nil;

@interface OWAddress (PrivateParts)
+ (void)registerDefaultShortcutDictionary;
@end

@implementation OWAddress

+ (void)initialize;
{
    OBINITIALIZE;

    _filterRegularExpressionLock = [[NSLock alloc] init];

    // Note: If this changes, it should also be changed in OmniWeb's OWShortcutPreferences.m since it has no way of getting at it.  (Perhaps it should be a default.)  Ugly, but for now we're maintaining this character set in two places.
    nonShortcutCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"./:"];

    uniqueKeyCount = 0;
    uniqueKeyCountLock = [[NSLock alloc] init];

    lowercaseEffectNameDictionary = [[NSMutableDictionary alloc] initWithCapacity:8];

    // Must be lowercase
    [lowercaseEffectNameDictionary setObject:[NSNumber numberWithInt:OWAddressEffectFollowInWindow] forKey:@"followinwindow"];
    [lowercaseEffectNameDictionary setObject:[NSNumber numberWithInt:OWAddressEffectNewBrowserWindow] forKey:@"newbrowserwindow"];
    [lowercaseEffectNameDictionary setObject:[NSNumber numberWithInt:OWAddressEffectOpenBookmarksWindow] forKey:@"openbookmarkswindow"];

    // Old effect names, for backward compatibility with OmniWeb 2
    [lowercaseEffectNameDictionary setObject:[NSNumber numberWithInt:OWAddressEffectFollowInWindow] forKey:@"follow"];
    [lowercaseEffectNameDictionary setObject:[NSNumber numberWithInt:OWAddressEffectNewBrowserWindow] forKey:@"x-popup"];
    [lowercaseEffectNameDictionary setObject:[NSNumber numberWithInt:OWAddressEffectOpenBookmarksWindow] forKey:@"x-as-list"];
    
    [[OFController sharedController] addStatusObserver:(id <OFControllerStatusObserver>)self];
}

+ (void)controllerDidInitialize:(OFController *)controller;
{
    [self _readDefaults];
    directoryIndexFilenamePreference = [OFPreference preferenceForKey:@"OWDirectoryIndexFilename"];
}

// Defaults

+ (NSDictionary *)shortcutDictionary;
{
    return _shortcutDictionary;
}

+ (void)setShortcutDictionary:(NSDictionary *)newShortcutDictionary;
{
    if (newShortcutDictionary == nil)
        return;

    _shortcutDictionary = [newShortcutDictionary copy];
    OFPreference *shortcutPreference = [OFPreference preferenceForKey:@"OW5AddressShortcuts"];
    [shortcutPreference setDictionaryValue:_shortcutDictionary];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[NSNotificationCenter defaultCenter] postNotificationName:OWAddressShortcutsDidChange object:nil];
}

+ (void)registerDefaultShortcutDictionary;
{
    NSMutableDictionary *mutableDefaultShortcuts = [[[OFPreference preferenceForKey:@"OW5AddressShortcuts"] defaultObjectValue] mutableCopy];
    
    // Localize the default '*' address, so people in Germany can end in .de instead of .com
    [mutableDefaultShortcuts setObject:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedStringFromTableInBundle(@"http://www.%@.com/", @"OWF", [OWAddress bundle], "default address format to use in your country when user just types a single word"), @"format", @"GET", @"method", @"www.*.com", @"name", nil] forKey:@"*"];

    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObject:mutableDefaultShortcuts forKey:@"OW5AddressShortcuts"]];
}

+ (void)reloadShortcutDictionaryFromDefaults;
{
    NSMutableDictionary *mutableShortcutDictionary;
    OFPreference *importedPreference;
    
    // Read preference
    mutableShortcutDictionary = [[[OFPreference preferenceForKey:@"OW5AddressShortcuts"] dictionaryValue] mutableCopy];

    // Import old shortcuts
    importedPreference = [OFPreference preferenceForKey:@"ImportedOW4Shortcuts"];
    if (![importedPreference boolValue]) {
        NSDictionary *oldDomain = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.omnigroup.OmniWeb"];
        NSDictionary *oldShortcutDictionary = [oldDomain objectForKey:@"OWAddressShortcuts"];
        if (oldShortcutDictionary != nil) {
            // -[NSUserDefaults dictionaryForKey:] returns nil if the stored value was originally a string, which is how we used to store everything with OFUserDefaults.  This lets us read the old format, then store the new format.
            oldShortcutDictionary = [(NSString *)oldShortcutDictionary propertyList];
        }
        
        for (NSString *key in oldShortcutDictionary) {
            if ([mutableShortcutDictionary objectForKey:key] != nil)
                continue;
            NSString *value = [oldShortcutDictionary objectForKey:key];
            if ([NSString isEmptyString:value])
                continue;
                
            NSDictionary *convertedShortcut = [NSDictionary dictionaryWithObjectsAndKeys:value, @"format", @"GET", @"method", nil];
            [mutableShortcutDictionary setObject:convertedShortcut forKey:key];
        }
        
        [importedPreference setBoolValue:YES];
        
    }
        
    if ([mutableShortcutDictionary objectForKey:@"*"] == nil) {
        // Localize the default '*' address, so people in Germany can end in .de instead of .com
        [mutableShortcutDictionary setObject:[NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedStringFromTableInBundle(@"http://www.%@.com/", @"OWF", [OWAddress bundle], "default address format to use in your country when user just types a single word"), @"format", @"GET", @"method", @"www.*.com", @"name", nil] forKey:@"*"];
    }
    
    [self setShortcutDictionary:mutableShortcutDictionary];
}

+ (void)reloadAddressFilterArrayFromDefaults;
{
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

    [_filterRegularExpressionLock lock];

    _filterRegularExpression = nil;
    _whitelistFilterRegularExpression = nil;

    NSArray *addressFilterArray = [userDefaults arrayForKey:OWAddressesToFilterDefaultName];
    if ([addressFilterArray count] > 0) {
        NSMutableArray *goodRegex = [NSMutableArray array];
        NSEnumerator *regexEnumerator = [addressFilterArray objectEnumerator];
        NSString *regexString;
        while ((regexString = [regexEnumerator nextObject])) {
            NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:regexString options:0 error:NULL];
            if (regex != nil) {
                [goodRegex addObject:regexString];
            } 
        }
        _filterRegularExpression = [[NSRegularExpression alloc] initWithPattern:[NSString stringWithFormat:@"(%@)", [goodRegex componentsJoinedByString:@")|("]] options:0 error:NULL];
    }

    NSArray *whitelistArray = [userDefaults arrayForKey:OWAddressesToAllowDefaultName];
    if ([whitelistArray count] > 0) {
        NSMutableArray *goodRegex = [NSMutableArray array];
        NSEnumerator *regexEnumerator = [whitelistArray objectEnumerator];
        NSString *regexString;
        while ((regexString = [regexEnumerator nextObject])) {
            NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:regexString options:0 error:NULL];
            if (regex != nil) {
                [goodRegex addObject:regexString];
            } 
        }
        _whitelistFilterRegularExpression = [[NSRegularExpression alloc] initWithPattern:[NSString stringWithFormat:@"(%@)", [goodRegex componentsJoinedByString:@")|("]] options:0 error:NULL];
    }
    [_filterRegularExpressionLock unlock];
}

+ (void)addAddressToWhitelist:(OWAddress *)anAddress;
{
    OFPreferenceWrapper *defaults = [OFPreferenceWrapper sharedPreferenceWrapper];
    NSString *addressString = [[anAddress addressString] regularExpressionForLiteralString];
    
    // Add to whitelist
    NSMutableArray *whiteList = [NSMutableArray arrayWithArray:[defaults arrayForKey:OWAddressesToAllowDefaultName]];
    if (![whiteList containsObject:addressString]) {
        [whiteList addObject:addressString];
        [defaults setObject:whiteList forKey:OWAddressesToAllowDefaultName];
    }
    
    // Remove from blacklist
    NSMutableArray *blackList = [NSMutableArray arrayWithArray:[defaults arrayForKey:OWAddressesToFilterDefaultName]];
    if ([blackList containsObject:addressString]) {
        [blackList removeObject:addressString];
        [defaults setObject:blackList forKey:OWAddressesToFilterDefaultName];
    }
    
    [self reloadAddressFilterArrayFromDefaults];
}

+ (void)addAddressToBlacklist:(OWAddress *)anAddress;
{
    OFPreferenceWrapper *defaults = [OFPreferenceWrapper sharedPreferenceWrapper];
    NSString *addressString = [[anAddress addressString] regularExpressionForLiteralString];
    
    // Remove from whitelist if present
    NSMutableArray *whiteList = [NSMutableArray arrayWithArray:[defaults arrayForKey:OWAddressesToAllowDefaultName]];
    if ([whiteList containsObject:addressString]) {
        [whiteList removeObject:addressString];
        [defaults setObject:whiteList forKey:OWAddressesToAllowDefaultName];
    }

    // Add to blacklist if not present
    NSMutableArray *blackList = [NSMutableArray arrayWithArray:[defaults arrayForKey:OWAddressesToFilterDefaultName]];
    if (![blackList containsObject:addressString]) {
        [blackList addObject:addressString];
        [defaults setObject:blackList forKey:OWAddressesToFilterDefaultName];
    }

    [self reloadAddressFilterArrayFromDefaults];
}

//

+ (NSString *)stringForEffect:(OWAddressEffect)anEffect;
{
    switch (anEffect) {
    case OWAddressEffectFollowInWindow:
	return @"FollowInWindow";
    case OWAddressEffectNewBrowserWindow:
	return @"NewBrowserWindow";
    case OWAddressEffectOpenBookmarksWindow:
	return @"OpenBookmarksWindow";
    }
    return nil;
}

+ (OWAddressEffect)effectForString:(NSString *)anEffectString;
{
    OWAddressEffect newEffect = OWAddressEffectFollowInWindow;

    if (anEffectString && ![(id)anEffectString isNull]) {
        NSNumber *effectNumber;

        effectNumber = [lowercaseEffectNameDictionary objectForKey:[anEffectString lowercaseString]];
        if (effectNumber)
            newEffect = [effectNumber intValue];
    }
    return newEffect;
}

static OWAddress *
addressForShortcut(NSString *originalString)
{
    NSDictionary *shortcutDictionary;
    NSRange spaceRange;
    NSDictionary *shortcutDefinition;
    NSString *shortcutFormat;
    NSString *shortcutKey, *shortcutParameter;
    NSString *formattedShortcut;

    /* Algorithm (more or less --- this code is weird [wim]):
        - Split the string at the first space, into a key and a parameter.
        - As long as the key contains no "non-shortcut" characters, repeatedly expand it using the shortcut dictionary.
        - When it no longer matches anything in the shortcut dictionary, if it still contains no non-shortcut characters, apply the shortcut for "*".
    
        If you end up with a string other than the one you started with, return an address for it. Otherwise return nil.
    */

    shortcutDictionary = [OWAddress shortcutDictionary];
    
    spaceRange = [originalString rangeOfString:@" "];
    if (spaceRange.length != 0) { // Note: in 10.1.4, spaceRange.location is not guaranteed to be NSNotFound when the string is not found (and the length is 0).  Specifically, spaceRange is {5, 0} for the input "12345/".
        shortcutParameter = [NSString encodeURLString:[originalString substringFromIndex:NSMaxRange(spaceRange)] asQuery:YES leaveSlashes:YES leaveColons:YES];
    } else {
        shortcutParameter = @"";
    }
    if ([NSString isEmptyString:shortcutParameter])
        shortcutKey = originalString;
    else
        shortcutKey = [[originalString substringToIndex:spaceRange.location] stringByAppendingString:@"@"];
    if ([shortcutKey rangeOfCharacterFromSet:nonShortcutCharacterSet].location != NSNotFound)
        return nil;

    shortcutDefinition = [shortcutDictionary objectForKey:shortcutKey];
    if (shortcutDefinition == nil) {
        shortcutDefinition = [shortcutDictionary objectForKey:@"*"];
        shortcutKey = originalString;
        shortcutParameter = shortcutKey;
    }

    shortcutFormat = [shortcutDefinition objectForKey:@"format"];
    if (shortcutFormat == nil)
        return nil;
    
    formattedShortcut = [shortcutFormat stringByReplacingOccurrencesOfString:@"%@" withString:shortcutParameter];
    
    NSString *formattedQuery = nil;
    NSString *shortcutQuery = [shortcutDefinition objectForKey:@"formData"];
    if (shortcutQuery != nil)
        formattedQuery = [shortcutQuery stringByReplacingOccurrencesOfString:@"%@" withString:shortcutParameter];
    
    if ([[shortcutDefinition objectForKey:@"method"] isEqualToString:@"POST"]) {
        OWAddress *postAddress = [OWAddress addressWithURL:[OWURL urlFromDirtyString:formattedShortcut]];
        
        NSMutableDictionary *methodDictionary = [NSMutableDictionary dictionaryWithCapacity:2];
        
        // Set encoding
        NSString *encoding = [shortcutDefinition objectForKey:@"encoding" defaultObject:@""];
        if (encoding != nil && ![NSString isEmptyString:encoding] && ![encoding isEqualToString:@"application/x-www-form-urlencoded"]) {
#ifdef DEBUG
            NSLog(@"addressForShortcut(): unsupported encoding '%@'", encoding);
#endif
            return nil; // We don't understand this form encoding
        }
        [methodDictionary setObject:encoding forKey:OWAddressContentTypeMethodKey defaultObject:@""];
            
        // Set data (encode the address url)
        if (formattedQuery == nil)
            formattedQuery = [[OWURL urlFromDirtyString:formattedShortcut] query];
            
        NSData *data = [formattedQuery dataUsingEncoding:NSISOLatin1StringEncoding]; // Should we really be using latin1?
        if (data != nil)
            [methodDictionary setObject:data forKey:OWAddressContentDataMethodKey];
        
        postAddress = [postAddress addressWithMethodString:@"POST" methodDictionary:methodDictionary forceAlwaysUnique:YES];
                
        return postAddress;
    } else {
        OWURL *getURL = [OWURL urlFromDirtyString:formattedShortcut];
        if (formattedQuery != nil)
            getURL = [getURL urlForQuery:formattedQuery];
        return [OWAddress addressWithURL:getURL];
    }
}

static OWAddress *
addressForObviousHostname(NSString *string)
{
    NSString *scheme;

    scheme = nil;
    if ([string hasPrefix:@"http."] || [string hasPrefix:@"www."]  || [string hasPrefix:@"home."])
        scheme = @"http://";
    else if ([string hasPrefix:@"gopher."])
        scheme = @"gopher://";
    else if ([string hasPrefix:@"ftp."])
        scheme = @"ftp://";

    if (scheme)
        return [OWAddress addressWithURL:[OWURL urlFromDirtyString:[scheme stringByAppendingString:string]]];
    else
        return nil;
}

static OWAddress *
addressForNotSoObviousHostname(NSString *string)
{
    NSRange rangeOfColon, rangeOfSlash;
    OWAddress *address;

    rangeOfColon = [string rangeOfString:@":"];
    if (rangeOfColon.location != NSNotFound) {
        return nil;
    }

    address = addressForObviousHostname(string);
    if (address)
        return address;

    rangeOfSlash = [string rangeOfString:@"/"];
    if (rangeOfSlash.location == 0) {
        // "/System" -> "file:///System"
        return [OWAddress addressWithFilename:string];
    } else if (rangeOfSlash.location != NSNotFound) {
        NSString *host;

        // "omnigroup/products" --> "http://www.omnigroup.com/products"
        host = [string substringToIndex:rangeOfSlash.location];
        if ([host rangeOfString:@"."].location == NSNotFound) {
            address = addressForShortcut(host);
            if (address) {
                NSString *addressString;
                NSString *additionalPath;

                addressString = [address addressString];
                if (![addressString hasSuffix:@"/"])
                    addressString = [addressString stringByAppendingString:@"/"];
                additionalPath = [string substringFromIndex:NSMaxRange(rangeOfSlash)];
                return [OWAddress addressWithURL:[OWURL urlFromDirtyString:[addressString stringByAppendingString:additionalPath]]];
            }
        }
    }
    return [OWAddress addressWithURL:[OWURL urlFromDirtyString:[@"http://" stringByAppendingString:string]]];
}

+ (OWAddress *)addressWithURL:(OWURL *)aURL target:(NSString *)aTarget methodString:(NSString *)aMethodString methodDictionary:(NSDictionary *)aMethodDictionary effect:(OWAddressEffect)anEffect forceAlwaysUnique:(BOOL)shouldForceAlwaysUnique contextDictionary:(NSDictionary *)aContextDictionary;
{
    if (!aURL)
	return nil;
    return [[self alloc] initWithURL:aURL target:aTarget methodString:aMethodString methodDictionary:aMethodDictionary effect:anEffect forceAlwaysUnique:shouldForceAlwaysUnique contextDictionary:aContextDictionary];
}

+ (OWAddress *)addressWithURL:(OWURL *)aURL target:(NSString *)aTarget methodString:(NSString *)aMethodString methodDictionary:(NSDictionary *)aMethodDictionary effect:(OWAddressEffect)anEffect forceAlwaysUnique:(BOOL)shouldForceAlwaysUnique;
{
    return [self addressWithURL:aURL target:aTarget methodString:aMethodString methodDictionary:aMethodDictionary effect:anEffect forceAlwaysUnique:shouldForceAlwaysUnique contextDictionary:nil];
}

+ (OWAddress *)addressWithURL:(OWURL *)aURL target:(NSString *)aTarget effect:(OWAddressEffect)anEffect;
{
    if (!aURL)
	return nil;
    return [[self alloc] initWithURL:aURL target:aTarget effect:anEffect];
}

+ (OWAddress *)addressWithURL:(OWURL *)aURL;
{
    if (!aURL)
	return nil;
    return [[self alloc] initWithURL:aURL target:nil effect:OWAddressEffectFollowInWindow];
}

+ (OWAddress *)addressForString:(NSString *)anAddressString;
{
    if (anAddressString == nil)
	return nil;
    return [self addressWithURL:[OWURL urlFromString:anAddressString]];
}

+ (OWAddress *)addressForDirtyString:(NSString *)anAddressString;
{
    OWAddress *address;

    anAddressString = [OWURL cleanURLString:anAddressString];
    if ([NSString isEmptyString:anAddressString])
	return nil;
	
    // Did user enter a shortcut?  If so, use it.
    if ((address = addressForShortcut(anAddressString)))
         return address;

    // Did user type something without any ":"?  If so, prefix with "http://%@"
    if ((address = addressForNotSoObviousHostname(anAddressString)))
         return address;
         
    if ((address = [self addressWithURL:[OWURL urlFromDirtyString:anAddressString]]))
        return address;

    return [OWAddress addressWithURL:[OWURL urlFromDirtyString:[@"http://" stringByAppendingString:anAddressString]]];
}

+ (OWAddress *)addressWithFilename:(NSString *)filename;
{
    NSString *encodedPath;
    
    if (!filename)
	return nil;
    if ([filename hasPrefix:@"/"])
	filename = [filename substringFromIndex:1];
        
    encodedPath = [NSString encodeURLString:filename encoding:kCFStringEncodingUTF8 asQuery:NO leaveSlashes:YES leaveColons:YES];
    return [self addressWithURL:[OWURL urlWithScheme:@"file" netLocation:@"" path:encodedPath params:nil query:nil fragment:nil]];
}

+ (OWAddress *)addressFromNSURL:(NSURL *)nsURL;
{
    return [self addressWithURL:[OWURL urlFromNSURL:nsURL]];
}

//

- initWithURL:(OWURL *)aURL target:(NSString *)aTarget methodString:(NSString *)aMethodString methodDictionary:(NSDictionary *)aMethodDictionary effect:(OWAddressEffect)anEffect forceAlwaysUnique:(BOOL)shouldForceAlwaysUnique contextDictionary:(NSDictionary *)aContextDictionary;
{
    if (!(self = [super init]))
	return nil;

    url = aURL;
    target = aTarget;
    methodString = aMethodString != nil ? aMethodString : @"GET";
    methodDictionary = aMethodDictionary;
    flags.effect = anEffect;
    flags.forceAlwaysUnique = shouldForceAlwaysUnique;
    contextDictionary = aContextDictionary;

    return self;
}

- initWithURL:(OWURL *)aURL target:(NSString *)aTarget methodString:(NSString *)aMethodString methodDictionary:(NSDictionary *)aMethodDictionary effect:(OWAddressEffect)anEffect forceAlwaysUnique:(BOOL)shouldForceAlwaysUnique;
{
    return [self initWithURL:aURL target:aTarget methodString:aMethodString methodDictionary:aMethodDictionary effect:anEffect forceAlwaysUnique:shouldForceAlwaysUnique contextDictionary:nil];
}

- initWithURL:(OWURL *)aURL target:(NSString *)aTarget effect:(OWAddressEffect)anEffect;
{
    return [self initWithURL:aURL target:aTarget methodString:nil methodDictionary:nil effect:anEffect forceAlwaysUnique:NO contextDictionary:nil];
}

- initWithURL:(OWURL *)aURL;
{
    return [self initWithURL:aURL target:nil methodString:nil methodDictionary:nil effect:OWAddressEffectFollowInWindow forceAlwaysUnique:NO contextDictionary:nil];
}

- initWithArchiveDictionary:(NSDictionary *)dictionary;
{
    OBPRECONDITION(dictionary != nil);

    if (!(self = [super init]))
        return nil;

    url = [OWURL urlFromString:[dictionary objectForKey:@"url" defaultObject:@""]];
    target = [dictionary objectForKey:@"target" defaultObject:@""];
    methodString = [dictionary objectForKey:@"method" defaultObject:@"GET"];
    methodDictionary = [dictionary objectForKey:@"mdict"];
    flags.effect = [dictionary intForKey:@"effect" defaultValue:OWAddressEffectFollowInWindow];
    flags.forceAlwaysUnique = [dictionary boolForKey:@"unique" defaultValue:NO];
    contextDictionary = [dictionary objectForKey:@"context"];

    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    return [self initWithArchiveDictionary:[aDecoder decodePropertyList]];
}

// Queries

- (OWURL *)url;
{
    return url;
}

- (OWURL *)proxyURL;
{
    return [OWProxyServer proxyURLForURL:url];
}

- (NSString *)methodString;
{
    return methodString;
}

- (NSDictionary *)methodDictionary;
{
    return methodDictionary;
}

- (NSString *)target;
{
    return target;
}

- (NSString *)localFilename;
{
    NSString *scheme = [url scheme];
    if ([scheme isEqualToString:@"file"]) {
        NSString *path = [url path];
        if (path == nil) {
            path = [url schemeSpecificPart];
            if (path == nil)
                path = @"";
        }

        NSString *decodedPath = [NSString decodeURLString:path encoding:kCFStringEncodingUTF8];
        if ([decodedPath hasPrefix:@"~"])
            return decodedPath;
#ifdef WIN32
        return decodedPath; // file:/C:/tmp -> C:/tmp
#else
        return [@"/" stringByAppendingString:decodedPath]; // file:/tmp -> /tmp
#endif
    }
    return nil;
}

- (NSString *)addressString;
{
    return [url compositeString];
}

- (NSString *)stringValue;
{
    return [url compositeString];
}

// Effects

- (OWAddressEffect)effect;
{
    return flags.effect;
}

- (NSString *)effectString;
{
    return [OWAddress stringForEffect:flags.effect];
}

// Archiving

- (NSDictionary *)archiveDictionary;
{
    NSMutableDictionary *archiveDictionary;

    archiveDictionary = [NSMutableDictionary dictionary];
    
    [archiveDictionary setObject:[url compositeString] forKey:@"url" defaultObject:@""];
    [archiveDictionary setObject:target forKey:@"target" defaultObject:@""];
    [archiveDictionary setObject:methodString forKey:@"method" defaultObject:@"GET"];
    if (methodDictionary != nil)
        [archiveDictionary setObject:methodDictionary forKey:@"mdict"];
    [archiveDictionary setIntValue:flags.effect forKey:@"effect" defaultValue:OWAddressEffectFollowInWindow];
    [archiveDictionary setBoolValue:flags.forceAlwaysUnique forKey:@"unique" defaultValue:NO];
    if (contextDictionary != nil)
        [archiveDictionary setObject:contextDictionary forKey:@"context"];
    
    return archiveDictionary;
}

// Encoding protocol

- (void)encodeWithCoder:(NSCoder *)aCoder;
{
    [aCoder encodePropertyList:[self archiveDictionary]];
}

// Displaying an address

- (NSString *)drawLabel;
{
    return [url compositeString];
}

- (BOOL)isVisited;
{
#warning TODO [wiml nov2003] - implement me
    return NO;
}

- (BOOL)isSecure;
{
    return [url isSecure];
}

- (NSString *)bestKnownTitleWithFragment;
{
    NSString *title;
    NSString *fragment;
    
    title = [self bestKnownTitle];
    fragment = [url fragment];
    
    if (fragment && [fragment length])
        title = [title stringByAppendingFormat:@" (%@)", fragment];
        
    return title;
}

// Equality and hashing

- (NSUInteger)hash;
{
    return [url hash];
}

// Exactly the same URL
- (BOOL)isEqual:(id)anObject;
{
    OWAddress *otherAddress;

    if (self == anObject)
	return YES;
    if (anObject == nil)
        return NO;
    otherAddress = anObject;
    if ([otherAddress class] != [self class])
	return NO;
    if (flags.effect != otherAddress->flags.effect)
	return NO;
#warning TODO: why not compare target also?
    if (![url isEqual:otherAddress->url])
	return NO;
    if (![methodString isEqualToString:otherAddress->methodString])
	return NO;
    if (methodDictionary != otherAddress->methodDictionary && ![methodDictionary isEqual:otherAddress->methodDictionary])
	return NO;
    if (flags.forceAlwaysUnique || otherAddress->flags.forceAlwaysUnique)
        return NO;
    return YES;
}

// Not the same URL, but will fetch the same data. For example, if two URLs could differ only by the fragment, which would mean they have the same document.
- (BOOL)isSameDocumentAsAddress:(OWAddress *)otherAddress;
{
    if (!otherAddress)
        return NO;
    if (self == otherAddress || (self->cacheKey && (self->cacheKey == otherAddress->cacheKey)))
	return YES;
    return [[self cacheKey] isEqualToString:[otherAddress cacheKey]];
}

- (BOOL)representsFile;
{
    return [url path] ? YES : NO;
}

- (NSDictionary *)contextDictionary;
{
    return contextDictionary;
}

- (OWContentType *)probableContentTypeBasedOnPath;
{
    NSString *localFilename;
    
    if (![self representsFile])
        return [OWUnknownDataStreamProcessor unknownContentType];
    
    if ((localFilename = [self localFilename]) != nil)
        return [OWContentType contentTypeForFilename:localFilename isLocalFile:YES];
        
    return [OWContentType contentTypeForFilename:[url path] isLocalFile:NO];
}

// OWContent protocol

- (OWContentType *)contentType;
{
    // TODO: Is it OK for the content type of an address to vary over time?  Because it can when its proxy changes.  Perhaps the right way for this to be handled is for addresses to all have a constant "address" content type, which is handled by a processor which looks up the proxy and produces "url/http" (or whatever) content (with the proxy information as part of its context).

    OWURL *proxiedURL = [self proxyURL];
    if (proxiedURL != url) {
        // Normally, the content type of a proxied URL is the content type of the proxy it will use. This is not true for e.g. HTTPS, which requires special handling from the proxy. So, we find the processor we would normally use for this URL, and we ask it what content type a proxied URL should have.
        OWConversionPathElement *conversionPath;
        OWProcessorDescription *urlProcessor;
        
        conversionPath = [[url contentType] bestPathForTargetContentType:[OWContentType sourceContentType]];
        if (conversionPath != nil &&
            (urlProcessor = [OWProcessorDescription processorDescriptionForProcessorClassName:[[conversionPath link] processorClassName]]) != nil) {
            return [urlProcessor contentTypeForURL:url whenProxiedBy:proxiedURL];
        } else
            return [proxiedURL contentType];
    }
    return [url contentType];
}


- (BOOL)endOfData
{
    return YES;
}

- (BOOL)contentIsValid;
{
    return YES;
}

// OWAddress protocol

- (NSString *)cacheKey;
{
    if (cacheKey)
	return cacheKey;
	
    if (![self isAlwaysUnique]) {
	cacheKey = [url cacheKey];
	return cacheKey;
    }
    [uniqueKeyCountLock lock];
    cacheKey = [[NSString alloc] initWithFormat:@"%d", uniqueKeyCount++];
    [uniqueKeyCountLock unlock];
    return cacheKey;
}

- (NSString *)shortDisplayString;
{
    return [url shortDisplayString];
}

- (NSString *)bestKnownTitle;
{
    NSString *bestKnownTitle;

    bestKnownTitle = [OWDocumentTitle titleForAddress:self];
    if (bestKnownTitle)
        return bestKnownTitle;

    // We'd really prefer an actual title before we punt and return shortDisplayString, so let's assume http://www.apple.com/macosx is likely to have the the same title as http://www.apple.com/macosx/, but first we have to make sure the URL string with its path, lest we get struck by PHP voodoo.
    if (![NSString isEmptyString:[[self url] path]]) {
        if ([NSString isEmptyString:[[self url] params]] && [NSString isEmptyString:[[self url] query]] && [NSString isEmptyString:[[self url] fragment]]) {
            OWURL *newURL;

            newURL = [OWURL urlFromString:[[[self url] compositeString] stringByAppendingString:@"/"]];
            bestKnownTitle = [OWDocumentTitle titleForAddress:[OWAddress addressWithURL:newURL]];
            if (bestKnownTitle)
                return bestKnownTitle;
        }
    }

    return [self shortDisplayString];
}

- (BOOL)isAlwaysUnique;
{
    if (flags.forceAlwaysUnique)
	return YES;
    if (methodDictionary)
	return YES;
    return NO;
}

// Getting related addresses

// If you don't use the method with the processor context, below, then #fragments won't properly be based off of the current document in the cache.  Not always a problem, but be aware of it. 
- (OWAddress *)addressForRelativeString:(NSString *)relativeAddressString;
{
    return [self addressForRelativeString:relativeAddressString inProcessorContext:nil target:nil effect:OWAddressEffectFollowInWindow];
}

- (OWAddress *)addressForRelativeString:(NSString *)relativeAddressString target:(NSString *)aTarget effect:(OWAddressEffect)anEffect;
{
    return [self addressForRelativeString:relativeAddressString inProcessorContext:nil target:aTarget effect:anEffect];
}

- (OWAddress *)addressForRelativeString:(NSString *)relativeAddressString inProcessorContext:(id <OWProcessorContext>)pipeline target:(NSString *)aTarget effect:(OWAddressEffect)anEffect;
{
    relativeAddressString = [OWURL cleanURLString:relativeAddressString];
    if (![relativeAddressString hasPrefix:@"#"]) {
        // If it's not a fragment, life is easy.
        return [OWAddress addressWithURL:[url urlFromRelativeString:relativeAddressString] target:aTarget methodString:nil methodDictionary:nil effect:anEffect forceAlwaysUnique:NO contextDictionary:contextDictionary];
    } else {
        OWAddress *relativeAddress;

        // If we're given a fragment, it should be based off of the pipeline's address, not ourselves, because we may be the document's <base href=""> address, and fragments are a special case.
        if (pipeline != nil) {
            OWAddress *pipelineAddress;

            pipelineAddress = [pipeline contextObjectForKey:OWCacheArcSourceAddressKey];
            if (pipelineAddress == nil)
                pipelineAddress = [pipeline contextObjectForKey:OWCacheArcHistoryAddressKey];
            if (pipelineAddress != nil)
                return [pipelineAddress addressForRelativeString:relativeAddressString inProcessorContext:nil target:aTarget effect:anEffect];
        }

        relativeAddress = [OWAddress addressWithURL:[url urlFromRelativeString:relativeAddressString] target:aTarget methodString:nil methodDictionary:nil effect:anEffect forceAlwaysUnique:NO contextDictionary:contextDictionary];
        // Force the new address to use the exact same document in the cache as we use, EVEN if we are unique (eg, the result of a FORM or some such).  The advantage to this is that image maps in form results that use "#mapname" will not force a second fetch, which will cause a form to post twice.  Also, relative links in form documents don't cause a refetch.
        relativeAddress->cacheKey = [self cacheKey];

        return relativeAddress;
    }
}

//

- (OWAddress *)addressForDirtyRelativeString:(NSString *)relativeAddressString;
{
    OWAddress *address;

    if (relativeAddressString == nil)
        return self;

    relativeAddressString = [OWURL cleanURLString:relativeAddressString];
    if ([relativeAddressString length] == 0)
        return self;

    address = [OWAddress addressWithURL:[url urlFromRelativeString:relativeAddressString]];
    if (address != nil)
        return address;

    address = addressForObviousHostname(relativeAddressString);
    if (address != nil)
        return address;
	
    return [OWAddress addressWithURL:[OWURL urlFromString:[@"http://" stringByAppendingString:relativeAddressString]]];
}

//

- (OWAddress *)addressWithGetQuery:(NSString *)query;
{
    return [OWAddress addressWithURL:[url urlForQuery:query] target:target methodString:nil methodDictionary:nil effect:OWAddressEffectFollowInWindow forceAlwaysUnique:YES contextDictionary:contextDictionary];
}

- (OWAddress *)addressWithPath:(NSString *)aPath;
{
    return [OWAddress addressWithURL:[url urlForPath:aPath] target:target methodString:methodString methodDictionary:methodDictionary effect:flags.effect forceAlwaysUnique:flags.forceAlwaysUnique contextDictionary:contextDictionary];
}

- (OWAddress *)addressWithMethodString:(NSString *)newMethodString;
{
    if (methodString == newMethodString)
	return self;
    return [OWAddress addressWithURL:url target:target methodString:newMethodString methodDictionary:nil effect:flags.effect forceAlwaysUnique:flags.forceAlwaysUnique contextDictionary:contextDictionary];
}

- (OWAddress *)addressWithMethodString:(NSString *)newMethodString
  methodDictionary:(NSDictionary *)newMethodDictionary
  forceAlwaysUnique:(BOOL)shouldForceAlwaysUnique;
{
    return [OWAddress addressWithURL:url target:target methodString:newMethodString methodDictionary:newMethodDictionary effect:flags.effect forceAlwaysUnique:shouldForceAlwaysUnique contextDictionary:contextDictionary];
}

- (OWAddress *)addressWithTarget:(NSString *)newTarget;
{
    if (target == newTarget)
	return self;
    return [OWAddress addressWithURL:url target:newTarget methodString:methodString methodDictionary:methodDictionary effect:flags.effect forceAlwaysUnique:flags.forceAlwaysUnique contextDictionary:contextDictionary];
}

- (OWAddress *)addressWithEffect:(OWAddressEffect)newEffect;
{
    if (flags.effect == newEffect)
	return self;
    return [OWAddress addressWithURL:url target:target methodString:methodString methodDictionary:methodDictionary effect:newEffect forceAlwaysUnique:flags.forceAlwaysUnique contextDictionary:contextDictionary];
}

- (OWAddress *)addressWithForceAlwaysUnique:(BOOL)shouldForceAlwaysUnique;
{
    if (flags.forceAlwaysUnique == shouldForceAlwaysUnique)
	return self;
    return [OWAddress addressWithURL:url target:target methodString:methodString methodDictionary:methodDictionary effect:flags.effect forceAlwaysUnique:shouldForceAlwaysUnique contextDictionary:contextDictionary];
}

- (OWAddress *)createUniqueVersionOfAddress;
{
    return [OWAddress addressWithURL:url target:target methodString:methodString methodDictionary:methodDictionary effect:flags.effect forceAlwaysUnique:YES contextDictionary:contextDictionary];
}

- (OWAddress *)addressWithoutFragment;
{
    OWURL *urlWithoutFragment;

    urlWithoutFragment = [url urlWithoutFragment];
    if (url == urlWithoutFragment)
	return self;
    return [OWAddress addressWithURL:urlWithoutFragment target:target methodString:methodString methodDictionary:methodDictionary effect:flags.effect forceAlwaysUnique:flags.forceAlwaysUnique contextDictionary:contextDictionary];
}

- (OWAddress *)addressWithContextDictionary:(NSDictionary *)newContextDictionary;
{
// NSLog(@"Creating address with context dictionary %@", newContextDictionary);
    return [OWAddress addressWithURL:url target:target methodString:methodString methodDictionary:methodDictionary effect:flags.effect forceAlwaysUnique:flags.forceAlwaysUnique contextDictionary:newContextDictionary];
}

- (OWAddress *)addressWithContextObject:object forKey:(NSString *)key;
{
    NSMutableDictionary *mutableContextDictionary;
    
    mutableContextDictionary = [NSMutableDictionary dictionary];
    if (contextDictionary != nil)
        [mutableContextDictionary addEntriesFromDictionary:contextDictionary];
    if (object == nil)
        [mutableContextDictionary removeObjectForKey:key];
    else
        [mutableContextDictionary setObject:object forKey:key];
    if ([mutableContextDictionary count] == 0)
        mutableContextDictionary = nil;
    
    return [OWAddress addressWithURL:url target:target methodString:methodString methodDictionary:methodDictionary effect:flags.effect forceAlwaysUnique:flags.forceAlwaysUnique contextDictionary:mutableContextDictionary];
}



- (NSString *)suggestedFilename;
{
    NSString *urlPath;
    NSString *filename;

    urlPath = [url path];
    if ([urlPath hasSuffix:@"/"]) {
        filename = [directoryIndexFilenamePreference stringValue];
    } else {
        filename = [NSString decodeURLString:[urlPath lastPathComponent]];
        if ([NSString isEmptyString:filename])
            filename = NSLocalizedStringFromTableInBundle(@"download", @"OWF", [OWAddress bundle], @"default suggested filename if not html");
    }

    return filename;
}

// A URL can have any crud after the last '.' characther in the last path component.  We will only accept alphanumeric characters in the file extension, if for no other reason than NSWorkspace can crash on crazy inputs.
- (NSString *)suggestedFileType;
{
    NSString *filename;
    NSString *fileType;
    NSRange range;
    
    filename = [NSString decodeURLString:[[url path] lastPathComponent]];
    fileType = [filename pathExtension];
    range = [fileType rangeOfCharacterFromSet: [[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    if (range.length)
        return nil;
    return fileType;
}

// NSCopying protocol

- (id)copyWithZone:(NSZone *)zone
{
    OWURL *newURL = [url copyWithZone:zone];
    NSString *newTarget = [target copyWithZone:zone];
    NSString *newMethodString = [methodString copyWithZone:zone];
    NSDictionary *newMethodDictionary = [methodDictionary copyWithZone:zone];
    NSDictionary *newContextDictionary = [contextDictionary copyWithZone:zone];
        
    OWAddress *newAddress = [[[self class] allocWithZone:zone] initWithURL:newURL target:newTarget methodString:newMethodString methodDictionary:newMethodDictionary effect:flags.effect forceAlwaysUnique:flags.forceAlwaysUnique contextDictionary:newContextDictionary];
    
    return newAddress;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (url)
	[debugDictionary setObject:url forKey:@"url"];
    if (target)
	[debugDictionary setObject:target forKey:@"target"];
    if (methodString)
	[debugDictionary setObject:methodString forKey:@"methodString"];
    if (methodDictionary)
	[debugDictionary setObject:methodDictionary forKey:@"methodDictionary"];
    [debugDictionary setObject:[OWAddress stringForEffect:flags.effect] forKey:@"effect"];
    [debugDictionary setObject:flags.forceAlwaysUnique ? @"YES" : @"NO" forKey:@"forceAlwaysUnique"];

    return debugDictionary;
}

- (NSString *)shortDescription;
{
    return [[self url] shortDescription];
}

- (BOOL)isFiltered;
{
    if (OFISEQUAL([url scheme], @"data"))
        return NO;

    [_filterRegularExpressionLock lock];
    BOOL isFilteredAddress = (_filterRegularExpression != nil &&
                         [_filterRegularExpression hasMatchInString:[url compositeString]] &&
                         (_whitelistFilterRegularExpression == nil || ![_whitelistFilterRegularExpression hasMatchInString:[url compositeString]]));
    [_filterRegularExpressionLock unlock];
    
    return isFilteredAddress;
}

- (BOOL)isWhitelisted;
{
    [_filterRegularExpressionLock lock];
    BOOL isWhitelisted = (_whitelistFilterRegularExpression != nil && [_whitelistFilterRegularExpression hasMatchInString:[url compositeString]]);
    [_filterRegularExpressionLock unlock];
    
    return isWhitelisted;
}

// Type conversions

- (NSURL *)NSURL;
{
    return [url NSURL];
}

- (NSURLRequest *)NSURLRequest;
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[url NSURL]];
    [request setHTTPMethod:methodString];
    if (methodString != nil && [methodString isEqualToString:@"POST"]) {
        NSString *encodingMethod = [methodDictionary objectForKey:OWAddressContentTypeMethodKey];
        if (![NSString isEmptyString:encodingMethod])
            [request setValue:encodingMethod forHTTPHeaderField:@"Content-Type"];
        [request setHTTPBody:[methodDictionary objectForKey:OWAddressContentDataMethodKey]];
    }
#ifdef DEBUG_kc
    NSLog(@"-[%@ %@]: request=%@, method=%@, headers=%@, body=%@, address=%@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), request, [request HTTPMethod], [request allHTTPHeaderFields], [request HTTPBody], self);
#endif
    return request;
}

#pragma mark -

+ (void)_readDefaults;
{
    [self reloadAddressFilterArrayFromDefaults];
    [self registerDefaultShortcutDictionary];
    [self reloadShortcutDictionaryFromDefaults];
}

@end
