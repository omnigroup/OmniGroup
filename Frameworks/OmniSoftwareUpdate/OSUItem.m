// Copyright 2001-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUItem.h"

#import "OSUErrors.h"
#import "OSUInstaller.h"
#import <OmniSoftwareUpdate/OSUChecker.h>
#import "OSUPreferences-Items.h"

#import <OmniAppKit/NSFileManager-OAExtensions.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#ifdef DEBUG
    #define ITEM_DEBUG(...) do{ if(OSUItemDebug) NSLog(__VA_ARGS__); }while(0)
#else
    #define ITEM_DEBUG(...) do{  }while(0)
#endif

NSString * const OSUItemAvailableBinding = @"available";
NSString * const OSUItemSupersededBinding = @"superseded";
NSString * const OSUItemIgnoredBinding = @"ignored";
NSString * const OSUItemOldStableBinding = @"oldStable";

BOOL OSUItemDebug = NO;

#ifdef DEBUG
static off_t OSUItemSizeAdjustment = 0;
static BOOL OSURejectChecksums = NO;
#endif

static NSArray *_requireNodes(NSXMLElement *base, NSString *namespace, NSString *tag, NSError **outError)
{
    NSArray *nodes = namespace? [base elementsForLocalName:tag URI:namespace] : [base elementsForName:tag];
    if (!nodes || [nodes count] == 0) { // no matching nodes
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"RSS node contains no match for '%@'.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - expected to find a specific element in RSS feed but didn't"), tag];
        OSUError(outError, OSUUnableToParseSoftwareUpdateItem, description, nil);
        return nil;
    }
    
    return nodes;
}

static NSXMLNode *_requiredNode(NSXMLElement *base, NSString *namespace, NSString *tag, NSError **outError)
{
    NSArray *nodes = _requireNodes(base, namespace, tag, outError);
    if (!nodes)
        return nil;
    
    // For now, if there are multiple nodes, we'll take the last one.
    OBASSERT([nodes count] == 1);
    
    return [nodes lastObject];
}

static NSString *_requiredStringNode(NSXMLElement *base, NSString *namespace, NSString *tag, BOOL allowEmpty, NSError **outError)
{
    NSXMLNode *node = _requiredNode(base, namespace, tag, outError);
    if (!node)
        return nil;
    
    NSArray *stringNodes = [node objectsForXQuery:@"text()" error:outError];
    if (!stringNodes)
        return nil;
    
    NSXMLNode *stringNode = [stringNodes lastObject];

    // This XQuery will return an empty array for "<foo></foo>", but lets just ensure that this will never return an empty string.
    NSString *result = [stringNode stringValue];
    if ([NSString isEmptyString:result]) {
        /* result is nil, or zero-length */
        if (!allowEmpty) {
            NSString *description = [NSString stringWithFormat:@"Element <%@> contains no text.", tag];
            OSUError(outError, OSUUnableToParseSoftwareUpdateItem, description, nil);
            return nil;
        } else {
            return @"";
        }
    }

    return result;
}

static NSString *_optionalStringNode(NSXMLElement *elt, NSString *tag, NSString *childNamespace)
{
    if (!elt || [elt kind] != NSXMLElementKind)
        return nil;
    
    NSArray *nodes = childNamespace? [elt elementsForLocalName:tag URI:childNamespace] : [elt elementsForName:tag];
    if (!nodes || ![nodes count])
        return nil;
    
    NSString *stringValue = [[nodes objectAtIndex:0] stringValue];
    
    if (stringValue && ![NSString isEmptyString:stringValue])
        return stringValue;
    else
        return nil;
}

#define AssignRequiredString(var, ns, tag) do { \
    NSString *str = _requiredStringNode(element, ns, tag, NO, outError); \
    if (!str) { \
        if (OSUItemDebug) \
            NSLog(@"Ignoring item due to missing string node with tag '%@' in element:\n%@", (tag), (element)); \
        return nil; \
    } \
    var = [str copy]; \
} while(0)

static NSDictionary *FreeAttributes = nil;
static NSDictionary *PaidAttributes = nil;
static NSFont *itemFont = nil, *ignoredFont = nil;
static NSNumber *ignoredFontNeedsObliquity = nil;

@implementation OSUItem

+ (void)initialize;
{
    OBINITIALIZE;
    
    // Turns on debug logs about RSS items read/ignored.
    OSUItemDebug = [[NSUserDefaults standardUserDefaults] boolForKey:@"OSUItemDebug"];
#ifdef DEBUG
    NSNumber *itemSizeAdjustment = [[NSUserDefaults standardUserDefaults] objectForKey:@"OSUItemSizeAdjustment"];
    if (itemSizeAdjustment != nil) {
        OSUItemSizeAdjustment = (off_t)[itemSizeAdjustment integerValue];
    }
    OSURejectChecksums = [[NSUserDefaults standardUserDefaults] boolForKey:@"OSURejectChecksums"];
#endif
    
    NSFont *font = [NSFont controlContentFontOfSize:[NSFont systemFontSize]];
    
    NSFont *italicFont = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSItalicFontMask];
    NSNumber *lackingObliquity;
    if (!italicFont || [italicFont isEqual:font]) {
        italicFont = font;
        lackingObliquity = [[NSNumber alloc] initWithCGFloat:(CGFloat)0.35];
    } else {
        lackingObliquity = nil;
    }
    
    FreeAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:italicFont, NSFontAttributeName, [NSColor disabledControlTextColor], NSForegroundColorAttributeName, lackingObliquity, NSObliquenessAttributeName, nil];

    NSFont *boldFont = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSBoldFontMask];
    if (!boldFont)
        boldFont = font;
    NSColor *paidColor = [NSColor colorWithRed:0/255.0f green:128/255.0f blue:0.0f alpha:1.0f];
    PaidAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:boldFont, NSFontAttributeName, paidColor, NSForegroundColorAttributeName, nil];
    
    itemFont = font;
    ignoredFont = italicFont;
    ignoredFontNeedsObliquity = lackingObliquity;
}

+ (void)setSupersededFlagForItems:(NSArray *)items;
{
    // O(n^2) loop; we could maybe bucket these into groups to make this faster, but realistically the number of updates in the feed should be small anyway.  Optimize later if necessary.
    NSUInteger itemIndex, itemCount = [items count];
    for (itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        OSUItem *item = [items objectAtIndex:itemIndex];
        ITEM_DEBUG(@"Item %@:", [item shortDescription]);
        
        unsigned int peerIndex;
        for (peerIndex = 0; peerIndex < itemCount; peerIndex++) {
            OSUItem *peer = [items objectAtIndex:peerIndex];
            
            if (item == peer)
                continue;
            
            if ([peer available] && [peer supersedesItem:item]) {
                ITEM_DEBUG(@"\t...is superseded by %@", [peer shortDescription]);
                [item setSuperseded:YES];
                break;
            } else {
                // ITEM_DEBUG(@"\t...is not superseded by %@", [peer shortDescription]);
            }
        }
        
        if (![item superseded])
            ITEM_DEBUG(@"\tis not superseded by any other item");
    }
}

/* This predicate selects items which we might display in the panel. We filter out unavailable items (which run on an OS the user doesn't have) and superseded items (which are older than another item in the list on the same or stabler track). */
+ (NSPredicate *)availableAndNotSupersededPredicate;
{
    static NSPredicate *predicate = nil;
    
    if (!predicate)
        predicate = [NSPredicate predicateWithFormat:@"%K = YES AND %K = NO", OSUItemAvailableBinding, OSUItemSupersededBinding];
    return predicate;
}

/* This predicate selects items that are worth popping up a panel for. We include some items in the panel that aren't interesting enough to show the panel for, such as ignored items or downgrade-to-previous-stable-release items, and this predicate filters those out. Those items may still be of interest to the user if they explicitly ask for an update check, for example, but won't bring up an unsolicited dialog. */
+ (NSPredicate *)availableAndNotSupersededIgnoredOrOldPredicate;
{
    static NSPredicate *predicate = nil;
    
    if (!predicate)
        predicate = [NSPredicate predicateWithFormat:@"%K = YES AND %K = NO AND %K = NO AND %K = NO", OSUItemAvailableBinding, OSUItemSupersededBinding, OSUItemIgnoredBinding, OSUItemOldStableBinding];
    return predicate;
}

+ (NSPredicate *)availableOldStablePredicate;
{
    static NSPredicate *predicate = nil;
    
    if (!predicate)
        predicate = [NSPredicate predicateWithFormat:@"%K = YES AND %K = NO AND %K = YES", OSUItemAvailableBinding, OSUItemIgnoredBinding, OSUItemOldStableBinding];
    return predicate;
}

- (void)_updateIgnoredState:(id)sender
{
#if OSU_FULL
    BOOL amIgnored = [OSUPreferences itemIsIgnored:self];
    if (amIgnored != _ignored) {
        [self willChangeValueForKey:OSUItemIgnoredBinding];
        _ignored =  amIgnored;
        [self didChangeValueForKey:OSUItemIgnoredBinding];
    }
#else
    OBASSERT_NOT_REACHED("This code gets compiled when building from the workspace for MAS builds, but should never be linked/executed");
#endif
}

- initWithRSSElement:(NSXMLElement *)element error:(NSError **)outError;
{
    if (!(self = [super init]))
        return nil;

    NSString *versionString;
    AssignRequiredString(versionString, OSUAppcastXMLNamespace, @"buildVersion");
    _buildVersion = [[OFVersionNumber alloc] initWithVersionString:versionString];
    
    AssignRequiredString(versionString, OSUAppcastXMLNamespace, @"marketingVersion");
    _marketingVersion = [[OFVersionNumber alloc] initWithVersionString:versionString];
    
    AssignRequiredString(versionString, OSUAppcastXMLNamespace, @"minimumSystemVersion");
    _minimumSystemVersion = [[OFVersionNumber alloc] initWithVersionString:versionString];
    _available = YES; // Assume until told otherwise
    
    AssignRequiredString(_title, nil, @"title");
    
    NSString *trackString = _requiredStringNode(element, OSUAppcastXMLNamespace, @"updateTrack", YES, outError);
    if (!trackString)
        return nil; // An error
    if ([NSString isEmptyString:trackString])
        trackString = @""; // this is the release track.
    _track = [trackString copy];
    
    NSArray *priceNodes = [element elementsForLocalName:@"price" URI:OSUAppcastXMLNamespace];
    NSXMLElement *priceNode = (priceNodes && [priceNodes count])? [priceNodes lastObject] : nil;
    // The XML price should use '.' as the decimal separator
    NSString *priceString = [priceNode stringValue];
    if (priceString != nil &&
        [priceString rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet]].location != NSNotFound) {
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot parse price '%@' -- it should contain only digits and possibly a period as a decimal separator.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description"), priceString];
        if (OSUItemDebug)
            NSLog(@"Ignoring item due to invalid price string, '%@'\n%@", description, element);
        OSUError(outError, OSUUnableToParseSoftwareUpdateItem, description, nil);
        return nil;
    }
    if (![NSString isEmptyString:priceString]) {
        
        NSString *currency = [[priceNode attributeForName:@"currency"] stringValue];
        if (!currency) {
            // For now, we assume US dollars as the default currency.
            currency = @"USD";
        }
        
        _price = [[NSDecimalNumber alloc] initWithString:priceString];
        _currencyCode = [currency copy];
    }
    
    NSArray *packagePathExtensions = [OSUInstaller supportedPackageFormats];
    
    OSUChecker *checker = [OSUChecker sharedUpdateChecker];
    
    // If we have a valid non-expiring license, then the price should be shown as free (that is, you can update to this version w/o paying any money since you already did).
    NSString *licenseType = [checker licenseType];
    
    if (OFISEQUAL(licenseType, OSULicenseTypeExpiring) || OFISEQUAL(licenseType, OSULicenseTypeTrial)) {
        // Display *nothing* in the price column.  This might be a built-in demo license for a beta or a site license.  In lieu of displaying the right thing, let's display nothing instead of something possibly wrong ("free").  See <bug://43521> and <bug:///73711>
        _price = nil;
    } else if (OFNOTEQUAL(licenseType, OSULicenseTypeUnset) && OFNOTEQUAL(licenseType, OSULicenseTypeNone) && ([_marketingVersion componentAtIndex:0] == [[checker applicationMarketingVersion] componentAtIndex:0])) {
        _price = [[NSDecimalNumber zero] copy]; // display 'free' in the price column for users with a valid license
    }
    
    _publishDateString = _optionalStringNode(element, @"pubDate", nil);
    
    // Get the associated link for this item; failing that, use the link for the feed as a whole
    NSString *linkText = _optionalStringNode(element, @"link", nil);
    NSString *feedLinkText = _optionalStringNode((NSXMLElement *)[element parent], @"link", nil);
    BOOL itemHasIndividualLink = ![NSString isEmptyString:linkText];
    if (linkText && feedLinkText)
        linkText = [[NSURL URLWithString:linkText relativeToURL:[NSURL URLWithString:feedLinkText]] absoluteString];
    else if (!linkText && feedLinkText)
        linkText = feedLinkText;
    _notionalItemOrigin = [linkText copy]; // May be nil
    
    // Pick an enclosure.  For a while, we used dmgs as our primary packaging format.  But, hdiutil is unreliable, so we are switching to tar and/or zip files.
    // Note that we allow items without enclosures only if they have a link.
    {
        NSArray *enclosureNodes = _requireNodes(element, nil, @"enclosure", outError);
        if (!enclosureNodes && !itemHasIndividualLink) {
            if (OSUItemDebug)
                NSLog(@"Ignoring item without enclosures or link:\n%@", element);
            return nil;
        }

        NSXMLElement *bestEnclosureNode = nil;
        NSUInteger bestEnclosurePrecedence = [packagePathExtensions count];
        NSURL *bestEnclosureURL = nil;
        
        NSUInteger nodeIndex = [enclosureNodes count];
        while (nodeIndex--) {
            NSXMLElement *node = [enclosureNodes objectAtIndex:nodeIndex];
            
            NSString *urlString = [[node attributeForName:@"url"] stringValue];
            if (!urlString) {
                NSLog(@"Skipping enclosure without a URL.");
                continue;
            }
            
            NSURL *downloadURL = [NSURL URLWithString:urlString];
            if (!downloadURL) {
                NSLog(@"Skipping enclosure with unparsable URL '%@'", urlString);
                continue;
            }
            
            for (NSUInteger thisEnclosurePrecedence = 0; thisEnclosurePrecedence < bestEnclosurePrecedence; thisEnclosurePrecedence ++) {
                if ([[downloadURL pathExtension] isEqual:packagePathExtensions[thisEnclosurePrecedence]]) {
                    // This enclosure's suffix is in OSUInstaller's list of supported formats, and either it's the first/only enclosure we've found, or its suffix is closer to the start of the list than the last one we found (since this loop only goes up to bestEnclosurePrecedence, not to the end of the list of formats).
                    bestEnclosureNode = node;
                    bestEnclosurePrecedence = thisEnclosurePrecedence;
                    bestEnclosureURL = downloadURL;
                    break;
                }
            }
            
            if (OSUItemDebug && (bestEnclosureNode != node))
                NSLog(@"Ignoring enclosure with unsupported or less-preferred file extension:\n%@", node);
        }
        
        if (!bestEnclosureNode && !itemHasIndividualLink) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"No suitable enclosure found.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description - RSS feed does not have an enclosure that we can use");
            if (OSUItemDebug)
                NSLog(@"Ignoring item without any suitable enclosures:\n%@", element);
            OSUError(outError, OSUUnableToParseSoftwareUpdateItem, description, nil);
            return nil;
        } else if (bestEnclosureNode) {
            _downloadURL = [bestEnclosureURL copy];  // We already know this is non-nil, from the enclosure selection loop
            
            NSString *downloadSizeString = [[bestEnclosureNode attributeForName:@"length"] stringValue];
            _downloadSize = [NSString isEmptyString:downloadSizeString] ? 0 : [downloadSizeString unsignedLongLongValue];
            
            NSMutableDictionary *sums = [NSMutableDictionary dictionary];
            OFForEachObject([([NSArray arrayWithObjects:@"md5", @"sha1", @"sha256", @"ripemd160", nil]) objectEnumerator], NSString *, hashAlgo) {
                NSXMLNode *hashAttribute = [bestEnclosureNode attributeForLocalName:hashAlgo URI:OSUAppcastXMLNamespace];
                if (hashAttribute)
                    [sums setObject:[hashAttribute stringValue] forKey:hashAlgo];
            }
            if ([sums count]) {
                _checksums = [sums copy];
            }
        } else {
            /* We don't have an enclosure, but we do have an individual item link. */
            OBASSERT(_downloadURL == nil);
            OBASSERT(![NSString isEmptyString:_notionalItemOrigin]);
        }
    }
    
    
    NSString *releaseNotesURLString = _optionalStringNode(element, @"releaseNotesLink", OSUAppcastXMLNamespace);
    if (releaseNotesURLString) {
        _releaseNotesURL = [[NSURL alloc] initWithString:releaseNotesURLString];
        if (!_releaseNotesURL) {
            NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot parse release notes url '%@'.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"error description"), _releaseNotesURL];
            if (OSUItemDebug)
                NSLog(@"Ignoring unparsable release notes URL '%@' in item:\n%@", releaseNotesURLString, element);
            OSUError(outError, OSUUnableToParseSoftwareUpdateItem, description, nil);
            return nil;
        }
    }
    
    [OFPreference addObserver:self selector:@selector(_updateIgnoredState:) forPreference:[OSUPreferences ignoredUpdates]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateIgnoredState:) name:OSUTrackVisibilityChangedNotification object:nil];
    [self _updateIgnoredState:nil];
    
    return self;
}

- (void)dealloc;
{
    [OFPreference removeObserver:self forPreference:[OSUPreferences ignoredUpdates]];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OSUTrackVisibilityChangedNotification object:nil];
}

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)aKey
{
    if ([aKey isEqualToString:@"displayFont"] || [aKey isEqualToString:@"displayColor"])
        return [NSSet setWithObjects:OSUItemIgnoredBinding, OSUItemAvailableBinding, OSUItemOldStableBinding, nil];
    else
        return [super keyPathsForValuesAffectingValueForKey:aKey];
}

#pragma mark Item attributes

@synthesize buildVersion = _buildVersion;
@synthesize marketingVersion = _marketingVersion;
@synthesize minimumSystemVersion = _minimumSystemVersion;

@synthesize title = _title;
@synthesize track = _track;
@synthesize price = _price;

- (NSString *)displayName;
{
    if (_olderStable)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Downgrade: %@", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"software update item - if an item is presented as a downgrade option, use this to format its displayed title - placeholder is normal title"), _title];
    
    return _title;
}

- (NSFont *)displayFont
{
    if (_ignored || !_available || _olderStable)
        return ignoredFont;
    else
        return itemFont;
}

- (NSColor *)displayColor
{
    if (_ignored || !_available)
        return [NSColor disabledControlTextColor];
    else
        return [NSColor controlTextColor];
}

@synthesize downloadURL = _downloadURL;
@synthesize sourceLocation = _notionalItemOrigin;

- (NSURL *)releaseNotesURL;
{
    if (_releaseNotesURL)
        return _releaseNotesURL;
    
    static NSURL *noReleaseNotesURL = nil;
    if (!noReleaseNotesURL) {
        NSString *path = [OMNI_BUNDLE pathForResource:@"NoReleaseNotesAvailable" ofType:@"html"];
        if (path)
            noReleaseNotesURL = [[NSURL fileURLWithPath:path] copy];
    }
    
    return noReleaseNotesURL;
}

- (BOOL)isFree
{
    /* If _price is nil, that means we don't actually know the price. */
    return (_price != nil && [[NSDecimalNumber zero] isEqual:_price]);
}

- (NSString *)priceString;
{
    if (!_price)
        return nil;
    
    if ([[NSDecimalNumber zero] isEqual:_price]) {
        return NSLocalizedStringFromTableInBundle(@"free!", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"free upgrade price string - displayed in price column");
    }
    
    if (!_priceFormatter) {
        // Make sure that we display the feed's specified currency according to the user's specified locale.  For example, if the user is Australia, we need to specify that the price is in US dollars instead of just using '$'.
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        OBASSERT([formatter formatterBehavior] != NSDateFormatterBehavior10_0);
        [formatter setNumberStyle:NSNumberFormatterCurrencyStyle];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setCurrencyCode:_currencyCode];
        _priceFormatter = formatter;
    }
    
    return [_priceFormatter stringFromNumber:_price];
}

- (NSDictionary *)priceAttributesForStyle:(NSBackgroundStyle)cellStyle;
{
    if (!_price)
        return nil;
    
    NSDictionary *attributes;
    
    if ([[NSDecimalNumber zero] isEqual:_price]) {
        attributes = FreeAttributes;
    } else {
        attributes = PaidAttributes;
    }
    
    if (cellStyle == NSBackgroundStyleEmphasized) {
        // Don't colorize text in highlighted rows --- it's too dark to read.
        attributes = [attributes dictionaryWithObject:[NSColor selectedControlTextColor] forKey:NSForegroundColorAttributeName];
    }
    
    return attributes;
}

- (NSString *)downloadSizeString;
{
    /* If we don't have a download, or if we don't know its size, display nothing. */
    if (_downloadURL == nil || _downloadSize == 0)
        return nil;
    
    return [NSString abbreviatedStringForBytes:_downloadSize];
}

@synthesize publishDateString = _publishDateString;

- (BOOL)isNewsItem;
{
    return (_releaseNotesURL != nil && [NSString isEmptyString:self.downloadSizeString]);
}

#pragma mark Item state

@synthesize available = _available;

@synthesize isIgnored = _ignored;

- (void)setAvailablityBasedOnSystemVersion:(OFVersionNumber *)systemVersion;
{
    // same or greater is allowed
    BOOL available = [_minimumSystemVersion compareToVersionNumber:systemVersion] != NSOrderedDescending;

    if (available)
        ITEM_DEBUG(@"Item %@ is available on %@", [self shortDescription], [systemVersion cleanVersionString]);
    else
        ITEM_DEBUG(@"Item %@ is not available on %@", [self shortDescription], [systemVersion cleanVersionString]);
    
    [self setAvailable:available];
}

@synthesize superseded = _superseded;

- (BOOL)supersedesItem:(OSUItem *)peer;
{
    // This item supersedes 'peer' if this item is not on a less stable software update track, has same major marketing version (so their license applies equally to both) and the peer has an older version number.
    
    if ([[self class] compareTrack:[self track] toTrack:[peer track]] == OSUTrackLessStable) {
        /* We can't supersede a release that we are less stable than. */
        return NO;
    }
    
    if ([_marketingVersion componentAtIndex:0] != [[peer marketingVersion] componentAtIndex:0]) {
        /* We only supersede releases of the same major version. */
        return NO;
    }
    
    /* Otherwise, newer releases supersede older releases. */
    return ([_buildVersion compareToVersionNumber:[peer buildVersion]] == NSOrderedDescending);
}

@synthesize isOldStable = _olderStable;

- (NSString *)verifyFile:(NSString *)path
{
    BOOL didVerify = NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // _downloadSize of 0 indicates we don't know the size.
    if (_downloadSize != 0) {
        __autoreleasing NSError *err = nil;
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:&err];
        if (!attrs) {
            NSLog(@"Can't check file: %@", err);
            return [err localizedDescription];
        }
        
        off_t actualSize = [attrs fileSize];
#ifdef DEBUG
        actualSize += OSUItemSizeAdjustment;
#endif
        
        if (actualSize < _downloadSize) {
            return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The file is the wrong size (%@ too short). It might be corrupted.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"caution text - we downloaded a file, but it's smaller than it's supposed to be - warn that it might be damaged or even maliciously replaced"), [NSString abbreviatedStringForBytes:_downloadSize - actualSize]];
        } else if (actualSize > _downloadSize) {
            return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The file is the wrong size (%@ too long). It might be corrupted.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"caution text - it's actual size, but it seems much bigger to me - warn that it might be damaged or even maliciously replaced"), [NSString abbreviatedStringForBytes:actualSize - _downloadSize]];
        }
    }
    
    if (_checksums) {
        __autoreleasing NSError *fileError = nil;
        NSData *fileData = [[NSData alloc] initWithContentsOfFile:path options:NSDataReadingMapped error:&fileError];
        if (!fileData) {
            return [fileError localizedDescription];
        }
        
        NSMutableArray *badSums = [NSMutableArray array];
        OFForEachObject([_checksums keyEnumerator], NSString *, algo) {
            NSString *expectedString = [_checksums objectForKey:algo];
            NSData *hash = [fileData signatureWithAlgorithm:algo];
            if (hash) {
                NSData *expected;
                if ([expectedString length] < (2 * [hash length]))
                    expected = [[NSData alloc] initWithBase64EncodedString:expectedString options:NSDataBase64DecodingIgnoreUnknownCharacters];
                else
                    expected = [NSData dataWithHexString:expectedString error:NULL];
                if (![hash isEqualToData:expected])
                    [badSums addObject:algo];
                if (![algo isEqualToString:@"md5"])  /* MD5 doesn't really count any more. */
                    didVerify = YES;
#ifdef DEBUG
                if (OSURejectChecksums) {
                    [badSums addObject:algo];
                }
#endif
            } else {
#ifdef DEBUG
                NSLog(@"%@: (%@): Unknown hash algorithm \"%@\"", [self class], _title, algo);
#endif
            }
        }
        
        if ([badSums count]) {
            return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The file's checksum does not match (%@). It might be corrupted.", @"OmniSoftwareUpdate", OMNI_BUNDLE, @"caution text - we downloaded a file, but its checksum is not correct - warn that it might be damaged or even maliciously replaced. Parameter is name(s) of hash algorithms (md5, sha1, etc)"), [badSums componentsJoinedByComma]];
        }
    }
    
    // If we're returning success, and we actually did anything that might be called verification, remove the quarantine on the file.
    if (didVerify) {
        // Sandboxed applications cannot remove the quarantine attribute.
        //   LSSetItemAttribute will return noErr (but do nothing) when attempting to remove kLSItemQuarantineProperties.
        //   removexattr will return EPERM when attempting to remove com.apple.quarantine.
        //
        // OSUInstaller.sh will remove the quarantine attribute as the final step of the install.
        // We ignore success/failure here.
        
        [fm setQuarantineProperties:nil forItemAtURL:[NSURL fileURLWithPath:path] error:NULL];
    }
    
    return nil;  // indicate no warnings
}

#pragma mark Track ordering

#ifndef DEBUG
#define STATIC_FOR_RELEASE static
#else
#define STATIC_FOR_RELEASE
#endif

STATIC_FOR_RELEASE BOOL trackOrderingsAreCurrent = NO;
STATIC_FOR_RELEASE NSDictionary *knownTrackOrderings = nil;
NSDictionary *trackLocalizedStrings = nil;

static void loadFallbackTrackInfoIfNeeded(void)
{
    if (knownTrackOrderings == nil) {
        // Fallback track orderings. Normally we'll have gotten an up-to-date ordering graph from our OSU query.
        knownTrackOrderings = @{
            @"sneakypeek": [NSSet setWithArray:@[@"beta", @"rc"]],
            @"alpha": [NSSet setWithArray:@[@"beta", @"rc"]],
            @"beta": [NSSet setWithArray:@[@"rc"]],
            @"internal-test": [NSSet setWithArray:@[@"private-test", @"test", @"rc"]],
            @"private-test": [NSSet setWithArray:@[@"test", @"rc"]],
            @"test": [NSSet setWithArray:@[@"rc"]],
            @"rc": [NSSet set],
        };
        trackOrderingsAreCurrent = NO;
    }
}

/*
 Describes aTrack w.r.t othertrack:
 returns, e.g., OSUTrackLessStable if aTrack is less stable than otherTrack.
 */
+ (enum OSUTrackComparison)compareTrack:(NSString *)aTrack toTrack:(NSString *)otherTrack;
{
    OBASSERT(aTrack != nil);
    OBASSERT(otherTrack != nil);
    
    if ([aTrack isEqualToString:otherTrack])
        return OSUTrackOrderedSame;
    
    /* The final track is more stable than any other track, even if the other track is unknown */
    if ([NSString isEmptyString:aTrack])
        return OSUTrackMoreStable;
    if ([NSString isEmptyString:otherTrack])
        return OSUTrackLessStable;
    
    loadFallbackTrackInfoIfNeeded();
    
    NSSet *supers = [knownTrackOrderings objectForKey:aTrack];
    if (!supers) {
        // aTrack is unknown.
        return OSUTrackNotOrdered;
    } else if ([supers containsObject:otherTrack]) {
        // otherTrack is more stable than aTrack, therefore aTrack is less stable than otherTrack.
        return OSUTrackLessStable;
    }
    
    supers = [knownTrackOrderings objectForKey:otherTrack];
    if (!supers) {
        // aTrack is unknown.
        return OSUTrackNotOrdered;
    } else if ([supers containsObject:aTrack]) {
        // aTrack is more stable than otherTrack
        return OSUTrackMoreStable;
    }
    
    // Both tracks are known, but they have no particular ordering.
    return OSUTrackNotOrdered;
}

/*
 This returns an ordered, culled copy of the tracks in someTracks (which can be any enumerable collection of strings).
 
 - Tracks which are implied by other tracks are removed (eg, "rc" won't be included if "beta" is).
 - Tracks which are known are shuffled to the front.
 
 */
+ (NSArray *)dominantTracks:(id <NSFastEnumeration>)someTracks;
{
    NSMutableArray *result = [NSMutableArray array];
    
    /* Copy the track names to 'result', keeping only the dominant ones */
    for (NSString *track in someTracks) {
        if ([NSString isEmptyString:track])
            continue;
        
        NSUInteger ix = [result count];
        while(ix-- > 0) {
            NSString *otherTrack = [result objectAtIndex:ix];
            enum OSUTrackComparison order = [self compareTrack:track toTrack:otherTrack];
            
            switch(order) {
                case OSUTrackLessStable:
                    [result removeObjectAtIndex:ix];
                    break;
                case OSUTrackOrderedSame:
                case OSUTrackMoreStable:
                    goto doNotAddToResult;
                default:
                    break;
            }
        }
        [result addObject:track];
    doNotAddToResult:
        ;
    }
    
    /* Shuffle any unknown tracks to the end of the array */
    if (trackOrderingsAreCurrent && knownTrackOrderings) {
        NSUInteger ix = [result count];
        NSUInteger unknownInsertion = ix;
        while(ix-- > 0) {
            NSString *aTrack = [result objectAtIndex:ix];
            if (![knownTrackOrderings objectForKey:aTrack]) {
                [result removeObjectAtIndex:ix];
                unknownInsertion --;
                [result insertObject:aTrack atIndex:unknownInsertion];
            }
        }
    }
    
    return result;
}

+ (NSArray *)elaboratedTracks:(id <NSFastEnumeration>)someTracks;
{
    NSMutableArray *result = [NSMutableArray array];

    loadFallbackTrackInfoIfNeeded();
    for (NSString *aTrack in someTracks) {
        [result addObjectIfAbsent:aTrack];
        NSSet *more = [knownTrackOrderings objectForKey:aTrack];
        if (more) {
            for (NSString *anotherTrack in more) {
                [result addObjectIfAbsent:anotherTrack];
            }
        }
    }
    
    return result;
}

+ (BOOL)isTrack:(NSString *)aTrack includedIn:(NSArray *)someTracks;
{
    if ([NSString isEmptyString:aTrack])
        return YES;
    
    if ([someTracks containsObject:aTrack])
        return YES;
    
    for (NSString *selectedTrack in someTracks) {
        enum OSUTrackComparison order = [self compareTrack:aTrack toTrack:selectedTrack];
        if (order == OSUTrackMoreStable || order == OSUTrackOrderedSame)
            return YES;
    };
    
    return NO;
}

/* Returns the human language of a node by searching for xml:lang attributes. */
static NSString *nodeLanguage(NSXMLElement *elt)
{
    for(;;) {
        NSXMLNode *langAtt = [elt attributeForName:@"xml:lang"];
        if (langAtt)
            return [langAtt stringValue];
        
        NSXMLNode *parent = [elt parent];
        
        if (parent == nil || [parent kind] != NSXMLElementKind)
            return nil;
        
        elt = (NSXMLElement *)parent;
    }
}

static void collectText(NSMutableDictionary *into, NSXMLElement *trackinfo, NSString *nodename)
{
    NSArray *kids = [trackinfo elementsForLocalName:nodename URI:OSUAppcastTrackInfoNamespace];
    if (!kids || ![kids count])
        return;
    
    NSMutableDictionary *byLanguage = [[NSMutableDictionary alloc] init];
    OFForEachInArray(kids, NSXMLElement *, textfoNode, {
        NSString *lang = nodeLanguage(textfoNode);
        if (!lang)
            continue;
        [byLanguage setObject:[textfoNode stringValue] forKey:lang];
    });
    
    [into setObject:byLanguage forKey:nodename];
}

/* This does what -attributeForLocalName:URI: *should* do. */
static NSXMLNode *_attr(NSXMLElement *elt, NSString *localName, NSString *URI)
{
    NSXMLNode *attribute = [elt attributeForLocalName:localName URI:URI];
    if (attribute)
        return attribute;
    
    attribute = [elt attributeForName:localName];
    if (attribute) {
        NSString *uri = [attribute URI];
        if (uri == nil)
            uri = [elt URI];
        if (uri) {
            if ([URI isEqualToString:uri])
                return attribute;
            else
                return nil;
        }
    }
    
    return nil;
}

+ (void)processTrackInformation:(NSXMLDocument *)allTracks;
{
    NSArray *trackDecls = [allTracks objectsForXQuery:@"declare namespace t = \"http://www.omnigroup.com/namespace/omniappcast/trackinfo-v1\"; /t:tracks//t:track" error:NULL];
    if (!trackDecls || ![trackDecls count]) {
        NSLog(@"Can't parse track text (root element is <%@>)", [[allTracks rootElement] name]);
        return;
    }
    
    NSMutableDictionary *strings = [NSMutableDictionary dictionary];
    NSMutableDictionary *ordering = [NSMutableDictionary dictionary];
    
    OFForEachInArray(trackDecls, NSXMLElement *, trackNode, {
        NSXMLNode *trackNameAtt = _attr(trackNode, @"name", OSUAppcastTrackInfoNamespace);
        NSXMLNode *trackParentsAtt = _attr(trackNode, @"stabler", OSUAppcastTrackInfoNamespace);
        
        if (!trackNameAtt || !trackParentsAtt) {
            OBASSERT_NOT_REACHED("Track element is missing attributes");
            continue;
        }
        
        NSString *trackName = [trackNameAtt stringValue];
        NSArray *trackParents = [[[trackParentsAtt stringValue] stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        [ordering setObject:[NSSet setWithArray:trackParents] forKey:trackName];
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        collectText(info, trackNode, @"warning");
        collectText(info, trackNode, @"name");
        [strings setObject:info forKey:trackName];
    });
    
    BOOL didChange = NO;
    
    if (!knownTrackOrderings || ![ordering isEqual:knownTrackOrderings]) {
        knownTrackOrderings = [ordering copy];
        trackOrderingsAreCurrent = YES;
        didChange = YES;
    }
    
    if (!trackLocalizedStrings || ![strings isEqual:trackLocalizedStrings]) {
        trackLocalizedStrings = [strings copy];
        didChange = YES;
    }
    
    if (didChange)
        [[NSNotificationCenter defaultCenter] postNotificationName:OSUTrackInformationChangedNotification object:self userInfo:nil];
}

+ (NSDictionary *)informationForTrack:(NSString *)trackName;
{
    if (!trackName)
        return nil;
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    NSMutableDictionary *trackStrings = [trackLocalizedStrings objectForKey:trackName];
    if (trackStrings) {
        
        [result setBoolValue:YES forKey:@"isKnown"];
        
        OFForEachObject([trackStrings keyEnumerator], NSString *, stringKey) {
            NSDictionary *values = [trackStrings objectForKey:stringKey];
            /* Note that +preferredLocalizationsFromArray:forPreferences:nil does a very different thing from +preferredLocalizationsFromArray:. The latter method looks at the main bundle to get localization possibilities (it calls CFBundleCopyPreferredLocalizationsFromArray()), instead of just consulting the user's preferences (CFBundleCopyLocalizationsForPreferences()). (The Foundation docs are rather unclear on this point.) */
            NSArray *lang = [NSBundle preferredLocalizationsFromArray:[values allKeys] forPreferences:nil];
            NSString *localizedString;
            if (lang && [lang count])
                localizedString = [values objectForKey:[lang objectAtIndex:0]];
            else
                localizedString = [values objectForKey:@""];

            if (localizedString)
                [result setObject:localizedString forKey:stringKey];
        }
    }
    
    loadFallbackTrackInfoIfNeeded();
    BOOL isKnown = ([knownTrackOrderings objectForKey:trackName])? YES : NO;
    [result setBoolValue:isKnown forKey:@"isKnown" defaultValue:NO];
    [result setBoolValue:(isKnown && trackOrderingsAreCurrent) forKey:@"isCurrent"];
    
    return result;
}

#pragma mark -
#pragma mark Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    
    [dict setObject:_buildVersion forKey:@"buildVersion"];
    [dict setObject:_marketingVersion forKey:@"marketingVersion"];
    [dict setObject:_minimumSystemVersion forKey:@"minimumSystemVersion"];
    [dict setObject:_title forKey:@"title"];
    
    if (_track)
        [dict setObject:_track forKey:@"track"];
    
    if (_price)
        [dict setObject:_price forKey:@"price"];
    if (_currencyCode)
        [dict setObject:_currencyCode forKey:@"currencyCode"];
    
    if (_releaseNotesURL)
        [dict setObject:_releaseNotesURL forKey:@"releaseNotesURL"];
    if (_downloadURL)
        [dict setObject:_downloadURL forKey:@"downloadURL"];
    [dict setUnsignedLongLongValue:_downloadSize forKey:@"downloadSize" defaultValue:0];
    if (_checksums)
        [dict setObject:_checksums forKey:@"checksums"];
    if (_notionalItemOrigin)
        [dict setObject:_notionalItemOrigin forKey:@"link"];
    
    [dict setBoolValue:self.isNewsItem forKey:@"isNewsItem"];
    [dict setBoolValue:_available forKey:@"available"];
    [dict setBoolValue:_superseded forKey:@"superseded"];
    [dict setBoolValue:_ignored forKey:@"ignored" defaultValue:NO];
    
    return dict;
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p '%@' %@ %@>", NSStringFromClass([self class]), self, _title, [_buildVersion cleanVersionString], _track];
}

@end
