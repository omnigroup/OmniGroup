// Copyright 2014-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFRelativeDateParser-Internal.h"

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/OFController.h>
#endif

RCS_ID("$Id$");

NSString * _OFRelativeDateParserLocalizedStringFromTableInBundle(NSString *key, NSString *table, NSBundle *bundle, NSString *comment)
{
    static BOOL shouldUseRelativeStringHack = NO;
    static NSString *dateProcessingLocalization = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
        NSBundle *mainBundle = [OFController controllingBundle]; // For unit test bundles
#else
        NSBundle *mainBundle = [NSBundle mainBundle];
#endif
        BOOL isLocalized = NO;
        for (NSString *localization in [mainBundle localizations]) {
            if ([localization isEqualToString:@"Base"] || [localization isEqualToString:@"en"] || [localization isEqualToString:@"English"]) {
                continue;
            }
            
            isLocalized = YES;
            break;
        }

        // If the application is not localized, let's look up the strings from OmniFoundation's localized table anyway
        if (!isLocalized) {
            NSArray *languages = [[NSUserDefaults standardUserDefaults] arrayForKey:@"AppleLanguages"];
            NSSet *bundleLocalizations = [NSSet setWithArray:[bundle localizations]];
            
            for (NSString *localization in languages) {
                if ([bundleLocalizations containsObject:localization]) {
                    shouldUseRelativeStringHack = YES;
                    dateProcessingLocalization = [localization copy];
                    break;
                }
            }
        }
        
#ifdef OMNI_ASSERTIONS_ON
        if (!shouldUseRelativeStringHack) {
            OBASSERT([[mainBundle localizations] containsObject:@"en"]);
        }
#endif
    });
    
    if (shouldUseRelativeStringHack && dateProcessingLocalization != nil && [table isEqualToString:@"OFDateProcessing"]) {
        static NSDictionary *stringsTable = nil;
        if (stringsTable == nil) {
            NSString *path = [OMNI_BUNDLE pathForResource:table ofType:@"strings" inDirectory:nil forLocalization:dateProcessingLocalization];
            
            stringsTable = [[NSDictionary alloc] initWithContentsOfFile:path];
            OBPOSTCONDITION(stringsTable != nil);
        }
        
        NSString *localizedString = [stringsTable objectForKey:key];
        if (![NSString isEmptyString:localizedString]) {
            return localizedString;
        }
    }
    
    return [bundle localizedStringForKey:key value:@"" table:table];
}

