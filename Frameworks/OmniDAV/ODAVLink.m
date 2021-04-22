// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDAV/ODAVLink.h>
#import <OmniFoundation/OFStringScanner.h>
#import <OmniFoundation/CFDictionary-OFExtensions.h>

// See <https://tools.ietf.org/html/rfc8288>

NS_ASSUME_NONNULL_BEGIN

@implementation ODAVLink

static OFCharacterSet *TokenEndCharacterSet;

+ (void)initialize;
{
    OBINITIALIZE;

    TokenEndCharacterSet = [[OFCharacterSet alloc] initWithOFCharacterSet:[OFCharacterSet whitespaceOFCharacterSet]];
    [TokenEndCharacterSet addCharactersInString:@"=,;"];
}

+ (NSArray <ODAVLink *> *)linksWithHeaderValue:(NSString *)linkHeader;
{
    NSMutableArray <ODAVLink *> *links = [NSMutableArray array];
    OFStringScanner *scanner = [[OFStringScanner alloc] initWithString:linkHeader];

    while ([scanner hasData]) {
        if (![scanner scanUpToCharacterNotInOFCharacterSet:[OFCharacterSet whitespaceOFCharacterSet]]) {
            break;
        }

        // <url>
        if (![scanner scanString:@"<" peek:NO]) {
            break;
        }
        NSString *urlString = [scanner readFullTokenWithDelimiterCharacter:'>'];
        if (!urlString) {
            break;
        }
        if (![scanner scanString:@">" peek:NO]) {
            break;
        }

        // ws ;
        if (![scanner scanUpToCharacterNotInOFCharacterSet:[OFCharacterSet whitespaceOFCharacterSet]]) {
            break;
        }
        if (![scanner scanString:@";" peek:NO]) {
            break;
        }

        // parameters; `rel` is required and should only be present once (first should win if there are multiples).
        NSMutableDictionary *parameters = nil;
        NSString *rel = nil;

        while (YES) {
            // Not being super careful about the token rules here...
            if (![scanner scanUpToCharacterNotInOFCharacterSet:[OFCharacterSet whitespaceOFCharacterSet]]) {
                break;
            }

            NSString *key = [scanner readFullTokenWithDelimiterOFCharacterSet:TokenEndCharacterSet];
            if (!key) {
                break;
            }
            if (![scanner scanString:@"=" peek:NO]) {
                break;
            }

            if (![scanner scanUpToCharacterNotInOFCharacterSet:[OFCharacterSet whitespaceOFCharacterSet]]) {
                break;
            }

            NSString *value;
            if ([scanner scanString:@"\"" peek:NO]) {
                value = [scanner readFullTokenWithDelimiterCharacter:'"'];
                if (![scanner scanString:@"\"" peek:NO]) {
                    break;
                }
            } else {
                value = [scanner readFullTokenWithDelimiterOFCharacterSet:TokenEndCharacterSet];
            }
            if (!value) {
                break;
            }

            if (!rel && [key caseInsensitiveCompare:@"rel"] == NSOrderedSame) {
                rel = [value copy];
            } else {
                if (!parameters) {
                    parameters = OFCreateCaseInsensitiveKeyMutableDictionary();
                }
                parameters[key] = value;
            }
        }

        NSURL *URL = [NSURL URLWithString:urlString];
        if (!URL) {
            break;
        }
        if (!rel) {
            break;
        }

        ODAVLink *link = [[ODAVLink alloc] initWithURL:URL relation:rel parameters:parameters];
        [links addObject:link];

        if (![scanner scanUpToCharacterNotInOFCharacterSet:[OFCharacterSet whitespaceOFCharacterSet]]) {
            break;
        }
        if (![scanner scanString:@"," peek:NO]) {
            break;
        }
    }

    return links;
}

- initWithURL:(NSURL *)URL relation:(NSString *)relation parameters:(nullable NSDictionary *)parameters;
{
    _URL = [URL copy];
    _relation = [relation copy];
    _parameters = [parameters copy];

    return self;
}

@end

NS_ASSUME_NONNULL_END
