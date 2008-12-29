// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSXMLNode;
@class OFVersionNumber;

NSString * const OSUItemAvailableBinding;
NSString * const OSUItemSupersededBinding;

@interface OSUItem : OFObject
{
    NSXMLElement *_element;
    
    OFVersionNumber *_buildVersion;
    OFVersionNumber *_marketingVersion;
    OFVersionNumber *_minimumSystemVersion;
    
    NSString *_title;
    NSString *_track;
    
    NSDecimalNumber *_price;
    NSString *_currencyCode;
    
    NSURL *_releaseNotesURL;
    NSURL *_downloadURL;
    off_t _downloadSize;
    
    BOOL _available;
    BOOL _superseded;
}

+ (void)setSupersededFlagForItems:(NSArray *)items;
+ (NSPredicate *)availableAndNotSupersededPredicate;

- initWithRSSElement:(NSXMLElement *)element error:(NSError **)outError;

- (NSXMLElement *)element; // the original element

- (OFVersionNumber *)buildVersion;
- (OFVersionNumber *)marketingVersion;
- (OFVersionNumber *)minimumSystemVersion;

- (NSString *)title;
- (NSString *)track;
- (NSURL *)downloadURL;
- (NSURL *)releaseNotesURL;

- (NSAttributedString *)priceAttributedString;

- (BOOL)available;
- (void)setAvailable:(BOOL)available;
- (void)setAvailablityBasedOnSystemVersion:(OFVersionNumber *)systemVersion;

- (BOOL)superseded;
- (void)setSuperseded:(BOOL)superseded;

- (BOOL)supersedes:(OSUItem *)peer;

@end
