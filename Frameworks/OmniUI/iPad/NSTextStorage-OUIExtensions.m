// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/NSTextStorage-OUIExtensions.h>

#import <OmniUI/OUITextSelectionSpan.h>
#import <OmniUI/OUITextView.h>

RCS_ID("$Id$")

static NSDataDetector *_linkDataDectector;

@implementation NSTextStorage (OUIExtensions)

+ (NSDataDetector *)_linkDataDetector;
{
    static NSDataDetector *detector = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error = nil;
        NSTextCheckingType typesToDetect = (
//                                            NSTextCheckingTypeAddress |
//                                            NSTextCheckingTypePhoneNumber |
                                            NSTextCheckingTypeLink |
                                            (NSTextCheckingType)0 // or-ing 0 on the end for easier enabling/disabling of cases above
                                            );
        detector = [NSDataDetector dataDetectorWithTypes:typesToDetect error:&error];
        if (!detector) {
            OBASSERT_NOT_REACHED("Unable to create link data detector %@", error);
        }
    });
    return detector;
}

- (NSArray *)textSpansInRange:(NSRange)entireRange inTextView:(OUITextView *)textView;
{
    OBPRECONDITION(NSMaxRange(entireRange) <= [self length]); // Allow '==' for insertion point at the end of a text view
    
    // Return one span per run so that the higher level code can make different edits to each span (for example, turning on italic should keep the font face that was on each span or keep the boldness).
    
    NSMutableArray *spans = [NSMutableArray array];

    // An insertion point should be inspectable so we can control the typingAttributes from the inspector.
    if (entireRange.length == 0) {
        UITextRange *textRange = [textView textRangeForCharacterRange:entireRange];
        OUITextSelectionSpan *span = [[OUITextSelectionSpan alloc] initWithRange:textRange inTextView:textView];
        [spans addObject:span];
        return spans;
    }
    
    [self enumerateAttributesInRange:entireRange options:0 usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
        NSRange effective;
        /* NSDictionary *d = */ [self attributesAtIndex:range.location longestEffectiveRange:&effective inRange:range];
        UITextRange *textRange = [textView textRangeForCharacterRange:effective];
        OUITextSelectionSpan *span = [[OUITextSelectionSpan alloc] initWithRange:textRange inTextView:textView];
        [spans addObject:span];
    }];
    
    return spans;
}

- (NSTextStorage *)underlyingTextStorage;
{
    return self;
}

- (void)removeAllLinks;
{
    [self beginEditing];
    [self removeAttribute:NSLinkAttributeName range:NSMakeRange(0, self.length)];
    [self endEditing];
}

- (void)detectAppSchemeLinks;
{
    [self beginEditing];
    {
        // We iterate over the raw string so we aren't mutating the thing over which we're iterating. We ensure that mutation never changes the length of the string so that detected ranges correspond to attributed ranges.
        NSString *string = self.string;
        NSRange fullRange = NSMakeRange(0, string.length);
        
        NSUInteger location = fullRange.location, end = NSMaxRange(fullRange);
        
        while (location < end) {
            NSRange remainingRange = NSMakeRange(location, end - location);
            NSRegularExpression *scanRegex = [NSTextStorage _linkDataDetector];
            [scanRegex enumerateMatchesInString:string options:0 range:remainingRange usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
                NSRange matchRange = result.range;
                NSURL *linkURL = nil;
                switch (result.resultType) {
                    case NSTextCheckingTypeLink:
                        linkURL = _probablyAppScheme(result.URL) ? result.URL : nil;
                        break;
                        
                    default:
                        OBASSERT_NOT_REACHED(@"Received unexpected data detection result: %@", @(result.resultType));
                }
                if (linkURL != nil) {
                    [self addAttribute:NSLinkAttributeName value:linkURL range:matchRange];
                }
            }];
            location = NSMaxRange(remainingRange);
        }
    }
    [self endEditing];
}

static BOOL _probablyAppScheme(NSURL *url) {
    static NSSet *schemesThatUIDataDetectorsShouldHandle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // All permanent schemes from http://www.iana.org/assignments/uri-schemes/uri-schemes.xhtml as of 9/30/2016.
        NSArray *schemes = @[
                             @"aaa",
                             @"aaas",
                             @"about",
                             @"acap",
                             @"acct",
                             @"cap",
                             @"cid",
                             @"coap",
                             @"coaps",
                             @"crid",
                             @"data",
                             @"dav",
                             @"dict",
                             @"dns",
                             @"example",
                             @"file",
                             @"ftp",
                             @"geo",
                             @"go",
                             @"gopher",
                             @"h323",
                             @"http",
                             @"https",
                             @"iax",
                             @"icap",
                             @"im",
                             @"imap",
                             @"info",
                             @"ipp",
                             @"ipps",
                             @"iris",
                             @"iris.beep",
                             @"iris.lwz",
                             @"iris.xpc",
                             @"iris.xpcs",
                             @"jabber",
                             @"ldap",
                             @"mailto",
                             @"mid",
                             @"msrp",
                             @"msrps",
                             @"mtqp",
                             @"mupdate",
                             @"news",
                             @"nfs",
                             @"ni",
                             @"nih",
                             @"nntp",
                             @"opaquelocktoken",
                             @"pkcs11",
                             @"pop",
                             @"pres",
                             @"reload",
                             @"rtsp",
                             @"rtsps",
                             @"rtspu",
                             @"service",
                             @"session",
                             @"shttp",
                             @"sieve",
                             @"sip",
                             @"sips",
                             @"sms",
                             @"snmp",
                             @"soap.beep",
                             @"soap.beeps",
                             @"stun",
                             @"stuns",
                             @"tag",
                             @"tel",
                             @"telnet",
                             @"tftp",
                             @"thismessage",
                             @"tip",
                             @"tn3270",
                             @"turn",
                             @"turns",
                             @"tv",
                             @"urn",
                             @"vemmi",
                             @"vnc",
                             @"ws",
                             @"wss",
                             @"xcon",
                             @"xcon-userid",
                             @"xmlrpc.beep",
                             @"xmlrpc.beeps",
                             @"xmpp",
                             @"z39.50r",
                             @"z39.50s",
                             ];
        schemesThatUIDataDetectorsShouldHandle = [NSSet setWithArray:schemes];
    });
    NSString *scheme = url.scheme;
    if ([NSString isEmptyString:scheme]) {
        return NO;
    }
    
    BOOL handledScheme = [schemesThatUIDataDetectorsShouldHandle containsObject:scheme];
    
    // Assume everything else is an app-scheme that we'll link ourselves.
    return !handledScheme;
}

@end
