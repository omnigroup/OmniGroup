// Copyright 2001-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSUItem.h"

#import "OSUErrors.h"
#import "OSUInstaller.h"
#import "OSUChecker.h"

#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniFoundation/OFNull.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniSoftwareUpdate/OSUItem.m 104009 2008-08-14 00:21:08Z wiml $");

#if 0 && defined(DEBUG)
    #define DEBUG_FLAGS(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_FLAGS(format, ...) do {} while(0)
#endif

NSString * const OSUItemAvailableBinding = @"available";
NSString * const OSUItemSupersededBinding = @"superseded";

static BOOL OSUItemDebug = NO;

static NSArray *_requireNodes(NSXMLNode *base, NSString *path, NSError **outError)
{
    NSArray *nodes = [base objectsForXQuery:path error:outError];
    
    if (!nodes) // error in XQuery
        return nil;
    
    if ([nodes count] == 0) { // no results to XQuery
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"RSS node contains no match for '%@'.", nil, OMNI_BUNDLE, @"error description"), path];
        OSUError(outError, OSUUnableToParseSoftwareUpdateItem, description, nil);
        return nil;
    }
    
    return nodes;
}

static NSXMLNode *_requiredNode(NSXMLNode *base, NSString *path, NSError **outError)
{
    NSArray *nodes = _requireNodes(base, path, outError);
    if (!nodes)
        return nil;
    
    // For now, if there are multiple nodes, we'll take the last one.
    OBASSERT([nodes count] == 1);
    
    return [nodes lastObject];
}

static NSString *_requiredStringNode(NSXMLNode *base, NSString *path, NSError **outError)
{
    NSXMLNode *node = _requiredNode(base, path, outError);
    if (!node)
        return nil;
    
    NSArray *stringNodes = [node objectsForXQuery:@"text()" error:outError];
    if (!stringNodes)
        return nil;
    
    NSXMLNode *stringNode = [stringNodes lastObject];

    // This XQuery will return an empty array if for "<foo></foo>", but lets just ensure that this will never return an empty string.
    NSString *result = [stringNode stringValue];
    if ([NSString isEmptyString:result])
        return nil;
    
    return result;
}

#define AssignRequiredString(var, path) do { \
    NSString *str = _requiredStringNode(element, (path), outError); \
    if (!str) { \
        if (OSUItemDebug) \
            NSLog(@"Ignoring item due to missing string node with path '%@' in element:\n%@", (path), (element)); \
        [self release]; \
        return nil; \
    } \
    var = [str copy]; \
} while(0)

static NSDictionary *FreeAttributes = nil;
static NSDictionary *PaidAttributes = nil;

@implementation OSUItem

+ (void)initialize;
{
    OBINITIALIZE;
    
    // Turns on debug logs about RSS items read/ignored.
    OSUItemDebug = [[NSUserDefaults standardUserDefaults] boolForKey:@"OSUItemDebug"];
    
    NSFont *font = [NSFont userFontOfSize:[NSFont systemFontSize]];
    
    NSFont *italicFont = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSItalicFontMask];
    if (!italicFont)
        italicFont = font;

    FreeAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:italicFont, NSFontAttributeName, [NSColor disabledControlTextColor], NSForegroundColorAttributeName, nil];

    NSFont *boldFont = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSBoldFontMask];
    if (!boldFont)
        boldFont = font;
    NSColor *paidColor = [NSColor colorWithCalibratedRed:0/255.0 green:128/255.0 blue:0.0 alpha:1.0];
    PaidAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:boldFont, NSFontAttributeName, paidColor, NSForegroundColorAttributeName, nil];
}

+ (void)setSupersededFlagForItems:(NSArray *)items;
{
    // O(n^2) loop; we could maybe bucket these into groups to make this faster, but realistically the number of updates in the feed should be small anyway.  Optimize later if necessary.
    unsigned int itemIndex, itemCount = [items count];
    for (itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        OSUItem *item = [items objectAtIndex:itemIndex];
        DEBUG_FLAGS(@"Item %@:", [item shortDescription]);
        
        unsigned int peerIndex;
        for (peerIndex = 0; peerIndex < itemCount; peerIndex++) {
            OSUItem *peer = [items objectAtIndex:peerIndex];
            
            if (item == peer)
                continue;
            
            if ([peer supersedes:item]) {
                DEBUG_FLAGS(@"\t...is superseded by %@", [peer shortDescription]);
                [item setSuperseded:YES];
                break;
            } else {
                DEBUG_FLAGS(@"\t...is not superseded by %@", [peer shortDescription]);
            }
        }
        
        if (![item superseded])
            DEBUG_FLAGS(@"Item %@ is not superseded by any other item", [item shortDescription]);
    }
}

+ (NSPredicate *)availableAndNotSupersededPredicate;
{
    static NSPredicate *predicate = nil;
    
    if (!predicate)
        predicate = [[NSPredicate predicateWithFormat:@"%K = YES AND %K = NO", OSUItemAvailableBinding, OSUItemSupersededBinding] retain];
    return predicate;
}

- initWithRSSElement:(NSXMLElement *)element error:(NSError **)outError;
{
    _element = [element copy];
    
    NSString *versionString;
    AssignRequiredString(versionString, @"omniappcast:buildVersion");
    _buildVersion = [[OFVersionNumber alloc] initWithVersionString:versionString];
    [versionString release];
    
    AssignRequiredString(versionString, @"omniappcast:marketingVersion");
    _marketingVersion = [[OFVersionNumber alloc] initWithVersionString:versionString];
    [versionString release];
    
    AssignRequiredString(versionString, @"omniappcast:minimumSystemVersion");
    _minimumSystemVersion = [[OFVersionNumber alloc] initWithVersionString:versionString];
    [versionString release];
    
    AssignRequiredString(_title, @"title");
    
    // AssignRequiredString doesn't allow empty strings, but we allow the track to be empty
    {
        NSXMLNode *node = _requiredNode(element, @"omniappcast:updateTrack", outError);
        if (!node)
            return nil;
        
        NSArray *stringNodes = [node objectsForXQuery:@"text()" error:outError];
        NSXMLNode *stringNode = [stringNodes lastObject];
        
        _track = [[stringNode stringValue] copy];
        if (!_track)
            _track = @""; // this is the release track.
    }
    
    // The XML price should use '.' as the decimal separator
    NSString *priceString;
    AssignRequiredString(priceString, @"omniappcast:price");

    if ([priceString rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet]].location != NSNotFound) {
        NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot parse price '%@' -- it should contain only digits and possibly a period as a decimal separator.", nil, OMNI_BUNDLE, @"error description"), priceString];
        if (OSUItemDebug)
            NSLog(@"Ignoring item due to invalid price string, '%@'\n%@", description, element);
        [priceString release];
        OSUError(outError, OSUUnableToParseSoftwareUpdateItem, description, nil);
        return nil;
    }
    _price = [[NSDecimalNumber alloc] initWithString:priceString];
    [priceString release];

    NSXMLNode *priceNode = _requiredNode(element, @"omniappcast:price", outError); // redundant since we just looked this up above
    if (!priceNode) {
        [self release];
        return nil;
    }
    _currencyCode = [[(NSXMLElement *)priceNode attributeForName:@"currency"] stringValue];
    if (!_currencyCode) {
        // For now, we assume US dollars as the default currency.
        _currencyCode = @"USD";
    }
    
    // If we have a valid non-expiring license, then the price should be shown as free (that is, you can update to this version w/o paying any money since you already did).
    NSString *licenseType = [[OSUChecker sharedUpdateChecker] licenseType];
    
    if (OFISEQUAL(licenseType, OSULicenseTypeExpiring)) {
        // Display *nothing* in the price column.  This might be a built-in demo license for a beta or a site license.  In lieu of displaying the right thing, let's display nothing instead of something possibly wrong ("free").  See <bug://43521>
        [_price release];
        _price = nil;
    } else if (OFNOTEQUAL(licenseType, OSULicenseTypeUnset) && OFNOTEQUAL(licenseType, OSULicenseTypeNone) && ([_marketingVersion componentAtIndex:0] == [[OSUChecker runningMarketingVersion] componentAtIndex:0])) {
        [_price release];
        _price = [[NSDecimalNumber zero] copy]; // display 'free' in the price column for users with a valid license
    }
    
    // Pick an enclosure.  For a while, we used dmgs as our primary packaging format.  But, hdiutil is unreliable as a programatic interface, so we are switching to zip.
    // For now, prefer dmg but handle multiple enclosures.  Once this change, zip packages and the ability to consume them trickles out, we'll switch to zip as the primary format.
    {
        NSArray *enclosureNodes = _requireNodes(element, @"enclosure", outError);
        if (!enclosureNodes) {
            if (OSUItemDebug)
                NSLog(@"Ignoring item without enclosurs:\n%@", element);
            [self release];
            return nil;
        }

        NSXMLNode *bestEnclosureNode = nil;
        NSString *bestEnclosureFormat = nil;
        
        unsigned int nodeIndex = [enclosureNodes count];
        while (nodeIndex--) {
            NSXMLNode *node = [enclosureNodes objectAtIndex:nodeIndex];
            
            NSString *urlString = [[(NSXMLElement *)node attributeForName:@"url"] stringValue];
            if (!urlString) {
                NSLog(@"Skipping enclosure without a URL.");
                continue;
            }
            
            NSURL *downloadURL = [NSURL URLWithString:urlString];
            if (!downloadURL) {
                NSLog(@"Skipping enclosure with unparsable URL '%@'", urlString);
                continue;
            }
            
            NSString *enclosureFormat = [[downloadURL path] pathExtension];
            if (![[OSUInstaller supportedPackageFormats] containsObject:enclosureFormat]) {
                if (OSUItemDebug)
                    NSLog(@"Ignoring unsupported enclosure with format '%@' in item:\n%@", enclosureFormat, element);

                continue;
            }
            
            // If we haven't found any acceptable enclosure yet, or the one we found isn't our preferenc and this one *is*...
            if (!bestEnclosureNode || (OFNOTEQUAL(bestEnclosureFormat, [OSUInstaller preferredPackageFormat]) && OFISEQUAL(enclosureFormat, [OSUInstaller preferredPackageFormat]))) {
                //NSLog(@"%@ is better than %@", node, bestEnclosureNode);
                bestEnclosureNode = node;
                bestEnclosureFormat = enclosureFormat;
            }
        }
        
        if (!bestEnclosureNode) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"No suitable enclosure found.", nil, OMNI_BUNDLE, @"error description");
            if (OSUItemDebug)
                NSLog(@"Ignoring item without any suiteable enclosures:\n%@", element);
            OSUError(outError, OSUUnableToParseSoftwareUpdateItem, description, nil);
            return nil;
        }
    
    
        NSString *urlString = [[(NSXMLElement *)bestEnclosureNode attributeForName:@"url"] stringValue];
        _downloadURL = [[NSURL alloc] initWithString:urlString];
        if (!_downloadURL) {
            NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot parse enclosure url '%@'.", nil, OMNI_BUNDLE, @"error description"), urlString];
            if (OSUItemDebug)
                NSLog(@"Ignoring item with unparseable enclosure URL '%@':\n%@", urlString, element);
            OSUError(outError, OSUUnableToParseSoftwareUpdateItem, description, nil);
            [self release];
            return nil;
        }
        
        _downloadSize = [[[(NSXMLElement *)bestEnclosureNode attributeForName:@"length"] stringValue] unsignedLongLongValue];
    }
    
    
    NSArray *releaseNotesStringNodes = [[[element elementsForName:@"omniappcast:releaseNotesLink"] lastObject] objectsForXQuery:@"text()" error:outError];
    if (!releaseNotesStringNodes && *outError) {
        if (OSUItemDebug)
            NSLog(@"Ignoring item without release notes URL:\n%@", element);
        [self release];
        return nil;
    }
    
    NSString *releaseNotesURLString = [[releaseNotesStringNodes lastObject] stringValue];
    if (![NSString isEmptyString:releaseNotesURLString]) {
        _releaseNotesURL = [[NSURL alloc] initWithString:releaseNotesURLString];
        if (!_releaseNotesURL) {
            NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot parse release notes url '%@'.", nil, OMNI_BUNDLE, @"error description"), _releaseNotesURL];
            if (OSUItemDebug)
                NSLog(@"Ignoring item unparseable release notes URL '%@':\n%@", releaseNotesURLString, element);
            OSUError(outError, OSUUnableToParseSoftwareUpdateItem, description, nil);
            return nil;
        }
    }
    
    return self;
}

- (void)dealloc;
{
    [_element release];
    [_buildVersion release];
    [_marketingVersion release];
    [_minimumSystemVersion release];
    [_title release];
    [_track release];
    [_price release];
    [_currencyCode release];
    [_releaseNotesURL release];
    [_downloadURL release];
    [super dealloc];
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key;
{
    if ([key isEqualToString:OSUItemAvailableBinding])
        return NO;
    if ([key isEqualToString:OSUItemSupersededBinding])
        return NO;
    
    return [super automaticallyNotifiesObserversForKey:key];
}

- (NSXMLElement *)element; // the original element
{
    return _element;
}

- (OFVersionNumber *)buildVersion;
{
    return _buildVersion;
}

- (OFVersionNumber *)marketingVersion;
{
    return _marketingVersion;
}

- (OFVersionNumber *)minimumSystemVersion;
{
    return _minimumSystemVersion;
}

- (NSString *)title;
{
    return _title;
}

- (NSString *)track;
{
    return _track;
}

- (NSString *)displayName;
{
#if 0 // The appcast now appends the build version for the sneakypeak feed.
    // If we are on the release track, just display our title.  Otherwise, we want to include the exact bundle version as well.
    if ([NSString isEmptyString:_track] || [_track isEqualToString:@"release"])
        return _title;
    
    return [NSString stringWithFormat:@"%@ (v%@)", _title, [_buildVersion cleanVersionString]];
#endif
    return _title;
}

- (NSURL *)downloadURL;
{
    return _downloadURL;
}

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

- (NSAttributedString *)priceAttributedString;
{
    if (!_price)
        return nil;
    
    if ([[NSDecimalNumber zero] isEqual:_price]) {
        static NSAttributedString *freeAttributedString = nil;
        if (!freeAttributedString)
            freeAttributedString = [[NSAttributedString alloc] initWithString:NSLocalizedStringFromTableInBundle(@"free!", nil, OMNI_BUNDLE, @"free upgrade price string") attributes:FreeAttributes];
        return freeAttributedString;
    }
    
    // Make sure that we display the feed's specified currency according to the user's specified locale.  For example, if the user is Australia, we need to specify that the price is in US dollars instead of just using '$'.
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
    [formatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    [formatter setLocale:[NSLocale currentLocale]];
    [formatter setCurrencyCode:_currencyCode];
    
    NSString *priceString = [formatter stringFromNumber:_price];
    return [[[NSAttributedString alloc] initWithString:priceString attributes:PaidAttributes] autorelease];
}

- (NSString *)downloadSizeString;
{
    return [NSString abbreviatedStringForBytes:_downloadSize];
}

- (BOOL)available;
{
    return _available;
}

- (void)setAvailable:(BOOL)available;
{
    if (_available == available)
        return;
    [self willChangeValueForKey:OSUItemAvailableBinding];
    _available = available;
    [self didChangeValueForKey:OSUItemAvailableBinding];
}

- (void)setAvailablityBasedOnSystemVersion:(OFVersionNumber *)systemVersion;
{
    // same or greater is allowed
    BOOL available = [_minimumSystemVersion compareToVersionNumber:systemVersion] != NSOrderedDescending;

    if (available)
        DEBUG_FLAGS(@"Item %@ is available on %@", [self shortDescription], [systemVersion cleanVersionString]);
    else
        DEBUG_FLAGS(@"Item %@ is not available on %@", [self shortDescription], [systemVersion cleanVersionString]);
    
    [self setAvailable:available];
}

- (BOOL)superseded;
{
    return _superseded;
}

- (void)setSuperseded:(BOOL)superseded;
{
    if (_superseded == superseded)
        return;
    [self willChangeValueForKey:OSUItemSupersededBinding];
    _superseded = superseded;
    [self didChangeValueForKey:OSUItemSupersededBinding];
}

- (BOOL)supersedes:(OSUItem *)peer;
{
    // One item supersedes another if they are on the same software update track, same major marketing version and same minimum OS version and the peer has an older version number.
    
    if (OFNOTEQUAL(_track, [peer track]) ||
        ([_marketingVersion componentAtIndex:0] != [[peer marketingVersion] componentAtIndex:0]) ||
        ([_minimumSystemVersion compareToVersionNumber:[peer minimumSystemVersion]] != NSOrderedSame))
        return NO;
    
    return ([_buildVersion compareToVersionNumber:[peer buildVersion]] == NSOrderedDescending);
}

#pragma mark -
#pragma mark Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    
    [dict setObject:_element forKey:@"element"];
    [dict setObject:_buildVersion forKey:@"buildVersion"];
    [dict setObject:_marketingVersion forKey:@"marketingVersion"];
    [dict setObject:_minimumSystemVersion forKey:@"minimumSystemVersion"];
    [dict setObject:_title forKey:@"title"];
    
    if (_track)
        [dict setObject:_track forKey:@"track"];
    
    if (_price) {
        [dict setObject:_price forKey:@"price"];
        [dict setObject:_currencyCode forKey:@"currencyCode"];
    }
    
    if (_releaseNotesURL)
        [dict setObject:_releaseNotesURL forKey:@"releaseNotesURL"];
    [dict setObject:_downloadURL forKey:@"downloadURL"];
    
    [dict setObject:[NSNumber numberWithBool:_available] forKey:@"available"];
    [dict setObject:[NSNumber numberWithBool:_superseded] forKey:@"superseded"];
    
    return dict;
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p '%@' %@ %@>", NSStringFromClass([self class]), self, _title, [_buildVersion cleanVersionString], _track];
}

@end
