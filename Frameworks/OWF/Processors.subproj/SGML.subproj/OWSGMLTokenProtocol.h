// Copyright 1999-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

typedef enum {
    OWSGMLTokenTypeStartTag, OWSGMLTokenTypeEndTag, OWSGMLTokenTypeCData, OWSGMLTokenTypeComment, OWSGMLTokenTypeUnknown
} OWSGMLTokenType;

// Flags which alter the behavior of -sgmlStringWithQuotingFlags: and -[NSString stringWithEntitiesQuoted:].
// The default is to quote anything that might possibly need quoting, and to use plain numeric entities.
#define SGMLQuoting_AllowNonASCII         00001   // no &#12463; (e.g.)
#define SGMLQuoting_AllowAttributeMetas   00002   // no &quot;
#define SGMLQuoting_AllowPCDATAMetas      00004   // no &lt; or &gt;
#define SGMLQuoting_NamedEntities         00010   // use &lt; instead of &60;
#define SGMLQuoting_HexadecimalEntities   00020   // use &#x3c; instead of &60;
// Note from the above that ampersands are *always* entity-ized regardless of flags used.


@protocol OWSGMLToken <NSObject>
- (NSString *)sgmlString;
    // Returns the HTML source representation of this token
- (NSString *)sgmlStringWithQuotingFlags:(int)flags;
- (NSString *)string;
    // Returns a string representation of this token
- (OWSGMLTokenType)tokenType;
    // Returns the type of this token
@end
