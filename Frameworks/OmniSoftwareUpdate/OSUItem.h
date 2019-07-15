// Copyright 2007-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSXMLNode;
@class OFVersionNumber;

extern NSString * const OSUItemAvailableBinding;     // Depends on whether the user is running a late enough version of the OS
extern NSString * const OSUItemSupersededBinding;    // Depends on whether a more recent item is also available in the list
extern NSString * const OSUItemIgnoredBinding;       // Depends on whether the user has manually skipped this update

#define OSUAppcastXMLNamespace (@"http://www.omnigroup.com/namespace/omniappcast/v1")
#define OSUAppcastTrackInfoNamespace (@"http://www.omnigroup.com/namespace/omniappcast/trackinfo-v1")

enum OSUTrackComparison {
    OSUTrackLessStable = NSOrderedAscending,
    OSUTrackOrderedSame = NSOrderedSame,
    OSUTrackMoreStable = NSOrderedDescending,
    OSUTrackNotOrdered = 23 // Hail Eris.
};

#define OSUTrackInformationChangedNotification (@"OSUTrackInfoChanged")

OB_HIDDEN extern BOOL OSUItemDebug;

@interface OSUItem : OFObject
{
    OFVersionNumber *_buildVersion;
    OFVersionNumber *_marketingVersion;
    OFVersionNumber *_minimumSystemVersion;
    
    NSString *_title;
    NSString *_track;
    
    NSDecimalNumber *_price;
    NSString *_currencyCode;
    NSNumberFormatter *_priceFormatter; // Cached
    
    NSURL *_releaseNotesURL;
    NSURL *_downloadURL;
    off_t _downloadSize;
    NSDictionary *_checksums;
    NSString *_notionalItemOrigin;
    
    // Available: does the item run on this machine/OS?
    BOOL _available;
    // Superseded: is there another item available that's equivalent but newer?
    BOOL _superseded;
    // Ignored: Has the user chosen not to see this item (or the track it's on)?
    BOOL _ignored;
    // OldStable: Is this older than the current version, but more stable than it?
    BOOL _olderStable;
}

+ (void)setSupersededFlagForItems:(NSArray<OSUItem *> *)items;
+ (NSPredicate *)availableAndNotSupersededPredicate;
+ (NSPredicate *)availableAndNotSupersededIgnoredOrOldPredicate;
+ (NSPredicate *)availableOldStablePredicate;

+ (enum OSUTrackComparison)compareTrack:(NSString *)aTrack toTrack:(NSString *)otherTrack;
+ (NSArray<NSString *> *)dominantTracks:(id <NSFastEnumeration>)someTracks;
+ (NSArray<NSString *> *)elaboratedTracks:(id <NSFastEnumeration>)someTracks;
+ (BOOL)isTrack:(NSString *)aTrack includedIn:(NSArray<NSString *> *)someTracks;
+ (void)processTrackInformation:(NSXMLDocument *)allTracks;
+ (NSDictionary *)informationForTrack:(NSString *)trackName;

- initWithRSSElement:(NSXMLElement *)element error:(NSError **)outError;

@property (readonly,nonatomic) OFVersionNumber *buildVersion;
@property (readonly,nonatomic) OFVersionNumber *marketingVersion;
@property (readonly,nonatomic) OFVersionNumber *minimumSystemVersion;

@property (readonly,nonatomic) NSString *title;
@property (readonly,nonatomic) NSString *track;
@property (readonly,nonatomic) NSURL *downloadURL;
@property (readonly,nonatomic) NSURL *releaseNotesURL;
@property (readonly,nonatomic) NSString *sourceLocation;
@property (readonly,nonatomic) NSString *displayName;
@property (readonly,nonatomic) NSFont *displayFont;
@property (readonly,nonatomic) NSColor *displayColor;
@property (readonly,nonatomic) NSString *downloadSizeString;

@property (readonly,nonatomic) BOOL isNewsItem;
@property (readonly,nonatomic) NSString *publishDateString;

@property (readonly,nonatomic) NSNumber *price;
@property (readonly,nonatomic) BOOL isFree;
@property (readonly,nonatomic) NSString *priceString;
- (NSDictionary *)priceAttributesForStyle:(NSBackgroundStyle)cellStyle;

@property (readwrite,nonatomic) BOOL available;
- (void)setAvailablityBasedOnSystemVersion:(OFVersionNumber *)systemVersion;
@property (readonly,nonatomic) BOOL isIgnored;
@property (readwrite,nonatomic) BOOL superseded;
- (BOOL)supersedesItem:(OSUItem *)peer;
@property (readwrite,nonatomic) BOOL isOldStable;

- (NSString *)verifyFile:(NSString *)local;

@end
