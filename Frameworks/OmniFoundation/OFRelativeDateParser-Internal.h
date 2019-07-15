// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRelativeDateParser.h>

// used by tests
typedef struct {
    NSUInteger day;
    NSUInteger month;
    NSUInteger year;
    __unsafe_unretained NSString *separator;
} DatePosition;

typedef struct {
    NSInteger day;
    NSInteger month;
    NSInteger year;
} DateSet;

@interface OFRelativeDateParser (OFInternalAPI)
- (DatePosition)_dateElementOrderFromFormat:(NSString *)dateFormat;
@end


NSString * _OFRelativeDateParserLocalizedStringFromTableInBundle(NSString *key, NSString *table, NSBundle *bundle, NSString *comment);

// Terrible hack so that we can load localized strings from OFDateProcessing.strings even if the main application is not currently localized
#undef NSLocalizedStringFromTableInBundle
#define NSLocalizedStringFromTableInBundle(key, tbl, bundle, comment) \
    _OFRelativeDateParserLocalizedStringFromTableInBundle((key), (tbl), (bundle), (comment))

