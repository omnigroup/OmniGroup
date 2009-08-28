// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLString.h>

#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSString-OFUnicodeCharacters.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFUnicodeUtilities.h>

#import <OmniFoundation/OFXMLBuffer.h>

RCS_ID("$Id$");

@interface OFXMLString (Private)
@end

@implementation OFXMLString

- initWithString: (NSString *) unquotedString quotingMask: (unsigned int) quotingMask newlineReplacment: (NSString *) newlineReplacment;
{
    OBPRECONDITION(unquotedString);
    OBPRECONDITION(((quotingMask & OFXMLNewlineEntityMask) == 0) == (newlineReplacment == nil));
    
    _unquotedString     = [unquotedString copy];
    _quotingMask        = quotingMask;
    _newlineReplacement = [newlineReplacment copy];
    return self;
}

- (void) dealloc;
{
    [_unquotedString release];
    [_newlineReplacement release];
    [super dealloc];
}

- (NSString *) unquotedString;
{
    return _unquotedString;
}

static NSString *CreateQuotedStringForEncoding(OFXMLString *self, CFStringEncoding encoding)
{
    return OFXMLCreateStringWithEntityReferencesInCFEncoding(self->_unquotedString, self->_quotingMask, self->_newlineReplacement, encoding);
}

- (NSString *)newQuotedStringForDocument:(OFXMLDocument *)doc;
{
    return CreateQuotedStringForEncoding(self, [doc stringEncoding]);
}

#pragma mark -
#pragma mark NSObject (OFXMLWriting)

- (BOOL)appendXML:(struct _OFXMLBuffer *)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
{
    NSString *text = [self newQuotedStringForDocument:doc];
    OBASSERT(text);
    if (text)
	OFXMLBufferAppendString(xml, (CFStringRef)text);
    [text release];
    return YES;
}

#pragma mark -
#pragma mark Comparison

- (BOOL)isEqual:(id)otherObject;
{
    // Could imagine we'd compare vs NSString too.
    OBPRECONDITION([otherObject isKindOfClass:[OFXMLString class]]);
    if (![otherObject isKindOfClass:[OFXMLString class]])
        return NO;
    OFXMLString *otherString = otherObject;
    
    // Short-circuit if our states are the same.
    if (OFISEQUAL(_unquotedString, otherString->_unquotedString) && _quotingMask == otherString->_quotingMask && OFISEQUAL(_newlineReplacement, otherString->_newlineReplacement))
        return YES;
    
    // Check if the resulting output would be the same, even if we get there a different way.
    NSString *quotedString = CreateQuotedStringForEncoding(self, kCFStringEncodingUTF8);
    NSString *otherQuotedString = CreateQuotedStringForEncoding(otherString, kCFStringEncodingUTF8);
    
    BOOL result = [quotedString isEqualToString:otherQuotedString];
    
    [quotedString release];
    [otherQuotedString release];
    
    return result;
}

@end

static void _OFXMLAppendCharacterEntityWithOptions(CFMutableStringRef result, uint32_t options, unichar c, CFStringRef characterEntity, CFStringRef namedEntity)
{
    switch (options) {
	case OFXMLCharacterFlagWriteNamedEntity:
            CFStringAppend(result, namedEntity);
	    break;
	case OFXMLCharacterFlagWriteCharacterEntity:
            CFStringAppend(result, characterEntity);
	    break;
	case OFXMLCharacterFlagWriteUnquotedCharacter:
            CFStringAppendCharacters(result, &c, 1);
	    break;
	default:
	    OBASSERT_NOT_REACHED("Bad options setting; character dropped");
	    break;
    }
}

// Replace characters with basic entities
static NSString *_OFXMLCreateStringWithEntityReferences(NSString *sourceString, unsigned int entityMask, NSString *optionalNewlineString)
{
    // Could maybe build smaller character sets for different entityMask combinations, but this should get most of the benefit (any special character we handle here).
    static CFCharacterSetRef entityCharacters = NULL;
    if (!entityCharacters) {
	// XML doesn't allow low ASCII characters.  See the 'Char' production in section 2.2 of the spec:
	//
	// Char := #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]	/* any Unicode character, excluding the surrogate blocks, FFFE, and FFFF. */
	CFMutableCharacterSetRef set = CFCharacterSetCreateMutable(kCFAllocatorDefault);
	CFCharacterSetAddCharactersInRange(set, (CFRange){0, 0x20});
	CFCharacterSetRemoveCharactersInRange(set, (CFRange){0x9, 1});
	CFCharacterSetRemoveCharactersInRange(set, (CFRange){0xA, 1});
	CFCharacterSetRemoveCharactersInRange(set, (CFRange){0xD, 1});
	
	// Additionally, XML uses a few special characters for elements, entities and quoting.  We'll write character entities for all of these (unless some quoting flags tell us differently)
	CFCharacterSetAddCharactersInString(set, CFSTR("&<>\"'\n"));
	
        entityCharacters = CFCharacterSetCreateCopy(kCFAllocatorDefault, set);
	CFRelease(set);
    }
    
    CFIndex charIndex, charCount = CFStringGetLength((CFStringRef)sourceString);
    CFRange fullRange = (CFRange){0, charCount};

    // Early out check
    if (!CFStringFindCharacterFromSet((CFStringRef)sourceString, entityCharacters, fullRange, 0/*options*/, NULL))
        return [sourceString retain];
    
    CFStringInlineBuffer charBuffer;
    CFStringInitInlineBuffer((CFStringRef)sourceString, &charBuffer, fullRange);

    CFMutableStringRef result = CFStringCreateMutable(kCFAllocatorDefault, 0);

    for (charIndex = 0; charIndex < charCount; charIndex++) {
        unichar c = CFStringGetCharacterFromInlineBuffer(&charBuffer, charIndex);
        if (c == '&') {
            CFStringAppend(result, (CFStringRef)@"&amp;");
        } else if (c == '<') {
            CFStringAppend(result, (CFStringRef)@"&lt;");
        } else if (c == '>' && (entityMask & OFXMLGtEntityMask) == OFXMLGtEntityMask) {
            CFStringAppend(result, (CFStringRef)@"&gt;");
	} else if (c == '\"') {
	    _OFXMLAppendCharacterEntityWithOptions(result, (entityMask >> OFXMLQuotCharacterOptionsShift) & OFXMLCharacterOptionsMask,
						   c, (CFStringRef)@"&#34;", (CFStringRef)@"&quot;");
	} else if (c == '\'') {
	    _OFXMLAppendCharacterEntityWithOptions(result, (entityMask >> OFXMLAposCharacterOptionsShift) & OFXMLCharacterOptionsMask,
						   c, (CFStringRef)@"&#39;", (CFStringRef)@"&apos;");
        } else if (c == '\n') { // 0xA
	    if (optionalNewlineString && (entityMask & OFXMLNewlineEntityMask) == OFXMLNewlineEntityMask)
                CFStringAppend(result, (CFStringRef)optionalNewlineString);
	    else
		CFStringAppendCharacters(result, &c, 1);
	} else if (c == '\t' || c == '\r') { // 0x9 || 0xD
            CFStringAppendCharacters(result, &c, 1);
	} else if (CFCharacterSetIsCharacterMember(entityCharacters, c)) {
	    // This is a low-ascii, non-whitespace byte and isn't allowed in XML character at all.  Drop it.
	    OBASSERT(c < 0x20 && c != 0x9 && c != 0xA && c != 0xD);
        } else
            // TODO: Might want to have a local buffer of queued characters to append rather than calling this in a loop.  Need to flush the buffer before each append above and after the end of the loop.
            CFStringAppendCharacters(result, &c, 1);
    }

    return (NSString *)result;
}

// Replace characters not representable in string encoding with numbered character references
NSString *OFXMLCreateStringInCFEncoding(NSString *sourceString, CFStringEncoding anEncoding)
{
    NSRange scanningRange = NSMakeRange(0, [sourceString length]);
    NSUInteger unrepresentableCharacterIndex = [sourceString indexOfCharacterNotRepresentableInCFEncoding:anEncoding range:scanningRange];
    if (unrepresentableCharacterIndex == NSNotFound) {
        // Vastly common case.
        return [sourceString retain];
    }

    // Some character of string needs quoting
    NSMutableString *resultString = [[NSMutableString alloc] init];

    while (scanningRange.length > 0) {
        unrepresentableCharacterIndex = [sourceString indexOfCharacterNotRepresentableInCFEncoding:anEncoding range:scanningRange];
        if (unrepresentableCharacterIndex == NSNotFound) {
            // Remainder of string has no characters needing quoting
            [resultString appendString:[sourceString substringWithRange:scanningRange]];
            break;
        }

        // Gather any characters before the unrepresentable characters.
        NSRange representableRange = NSMakeRange(scanningRange.location, unrepresentableCharacterIndex - scanningRange.location);
        if (representableRange.length > 0)
            [resultString appendString:[sourceString substringWithRange:representableRange]];

        // Then append a quoted form of the unrepresentable characters.
        NSRange composedRange = [sourceString rangeOfComposedCharacterSequenceAtIndex:unrepresentableCharacterIndex];
        unichar *composedCharacters = malloc(composedRange.length * sizeof(*composedCharacters));
        [sourceString getCharacters:composedCharacters range:composedRange];
        for (NSUInteger componentIndex = 0; componentIndex < composedRange.length; componentIndex++) {
            UnicodeScalarValue ch;  // this is a full 32-bit Unicode value

            if (OFCharacterIsSurrogate(composedCharacters[componentIndex]) == OFIsSurrogate_HighSurrogate &&
                (componentIndex + 1 < composedRange.length) &&
                OFCharacterIsSurrogate(composedCharacters[componentIndex+1]) == OFIsSurrogate_LowSurrogate) {
                ch = OFCharacterFromSurrogatePair(composedCharacters[componentIndex], composedCharacters[componentIndex+1]);
                componentIndex ++;
            } else {
                ch = composedCharacters[componentIndex];
            }

            [resultString appendFormat:@"&#%u;", ch];
        }
        free(composedCharacters);
        composedCharacters = NULL;
        
        // Skip past any stuff we've now handled.
        scanningRange.location = NSMaxRange(composedRange);
        scanningRange.length -= representableRange.length + composedRange.length;
    }

    // (this point is not reached if no changes are necessary to the source string)
    // resultString can be nil if the input was zero length.  Returning [sourceString retain] would work too, but static strings can be sent -release w/o doing anything, so this is ever-so-slightly faster.
    return resultString ? (NSString *)resultString : @"";
}

// 1. Replace characters with basic entities
// 2. Replace characters not representable in string encoding with numbered character references
NSString *OFXMLCreateStringWithEntityReferencesInCFEncoding(NSString *sourceString, unsigned int entityMask, NSString *optionalNewlineString, CFStringEncoding anEncoding)
{
    NSString *str;

    if (sourceString == nil)
        return nil;

    str = _OFXMLCreateStringWithEntityReferences(sourceString, entityMask, optionalNewlineString);
    OBASSERT(str);

    NSString *result = OFXMLCreateStringInCFEncoding(str, anEncoding);
    [str release];
    return result;
}

// TODO: This is nowhere near as efficient as it could be.  In particular, it shouldn't use NSScanner at all, much less create one for an input w/o any entity references.
NSString *OFXMLCreateParsedEntityString(NSString *sourceString)
{
    if (![sourceString containsString:@"&"])
        // Can't have any entity references then.
        return [sourceString copy];
    
    NSMutableString *result = [[NSMutableString alloc] init];
    NSScanner *scanner = [[NSScanner alloc] initWithString:sourceString];
    [scanner setCharactersToBeSkipped:nil];

    while ([scanner isAtEnd] == NO) {
        //NSLog(@"Start of loop, scan location: %d", [scanner scanLocation]);
        //NSLog(@"remaining string: %@", [sourceString substringFromIndex:[scanner scanLocation]]);
        NSString *scannedString;
        if ([scanner scanUpToString:@"&" intoString:&scannedString] == YES)
            [result appendString:scannedString];

        if ([scanner scanString:@"&" intoString:NULL] == YES) {
            NSString *entityName, *entityValue;

            entityName = nil;
            if ([scanner scanUpToString:@";" intoString:&entityName] == YES) {
                [scanner scanString:@";" intoString:NULL];

                entityValue = OFStringForEntityName(entityName);
                if (entityValue == nil) {
                    // OFStringForEntityName() will already have logged a warning
                    entityValue = [NSString stringWithFormat:@"&%@;", entityName];
                }

                [result appendString:entityValue];
            } else {
                NSLog(@"Misformed entity reference at location %d (not terminated)", [scanner scanLocation]);
                [result appendString:@"&"];
            }
        } else {
            // May just be at end of string.
        }
    }

    [scanner release];

    return result;
}

NSString *OFStringForEntityName(NSString *entityName)
{
    if ([entityName isEqual:@"lt"] == YES) {
        return @"<";
    } else if ([entityName isEqual:@"amp"] == YES) {
        return @"&";
    } else if ([entityName isEqual:@"gt"] == YES) {
        return @">";
    } else if ([entityName isEqual:@"quot"] == YES) {
        return @"\"";
    } else if ([entityName isEqual:@"apos"] == YES) {
        return @"'";
    } else if ([entityName hasPrefix:@"#x"] == YES &&
               [entityName length] > 2) {
        UnicodeScalarValue ch;

        ch = [[entityName substringFromIndex:2] hexValue];
        return [NSString stringWithCharacter:ch];
    } else if ([entityName hasPrefix:@"#"] == YES &&
               [entityName length] > 1) {
        // Avoid 'unichar' here because it is only 16 bits wide and will truncate Supplementary Plane characters
        UnicodeScalarValue ch;

        ch = [[entityName substringFromIndex:1] intValue];
        return [NSString stringWithCharacter:ch];
    }

    NSLog(@"Warning: Unknown entity: %@", entityName);

    return nil;
}



@implementation NSString (OFXMLWriting)
- (BOOL)appendXML:(struct _OFXMLBuffer *)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
{
    // Called when an element has a string as a direct child.
    NSString *text = OFXMLCreateStringWithEntityReferencesInCFEncoding(self, OFXMLBasicEntityMask, nil/*newlineReplacement*/, [doc stringEncoding]);
    OFXMLBufferAppendString(xml, (CFStringRef)text);
    [text release];
    return YES;
}
@end


#if 0
static void _OFAppendCharacterDataFromXMLTreeToString(CFXMLTreeRef aTree, NSMutableString *str)
{
    NSString *tmpString;
    CFXMLNodeRef xmlNode = CFXMLTreeGetNode(aTree);
    CFXMLNodeTypeCode nodeType = CFXMLNodeGetTypeCode(xmlNode);
    
    switch (nodeType) {
	case kCFXMLNodeTypeText:
	case kCFXMLNodeTypeCDATASection:
	    tmpString = (NSString *)CFXMLNodeGetString(xmlNode);
	    if (tmpString != nil)
		[str appendString:tmpString];
		break;
	case kCFXMLNodeTypeEntityReference:
	    tmpString = OFStringForEntityName((NSString *)CFXMLNodeGetString(xmlNode));
	    if (tmpString != nil)
		[str appendString:tmpString];
		break;
	default:
	    //NSLog(@"Ignoring node type %d (%@)", nodeType, NSStringFromXMLNodeType(nodeType));
	    break;
    }
    
    unsigned int childIndex, childCount = CFTreeGetChildCount(aTree);
    for (childIndex = 0; childIndex < childCount; childIndex++) {
        CFXMLTreeRef childTree = CFTreeGetChildAtIndex(aTree, childIndex);
        _OFAppendCharacterDataFromXMLTreeToString(childTree, str);
    }
}

NSString *OFCharacterDataFromXMLTree(CFXMLTreeRef aTree)
{
    NSMutableString *str = [NSMutableString string];
    _OFAppendCharacterDataFromXMLTreeToString(aTree, str);
    return str;
}
#endif

static void _OFCharacterDataFromElement(id element, NSMutableString *str)
{
    if ([element isKindOfClass:[NSString class]]) {
        [str appendString: element];
    } else if ([element isKindOfClass:[OFXMLElement class]]) {
        NSArray *children;
        unsigned int childIndex, childCount;
	
        children = [element children];
        childCount = [children count];
        for (childIndex = 0; childIndex < childCount; childIndex++)
            _OFCharacterDataFromElement([children objectAtIndex: childIndex], str);
    } else if ([element isKindOfClass: [OFXMLString class]]) {
        [str appendString: [element unquotedString]];
    }
}

NSString *OFCharacterDataFromElement(OFXMLElement *element)
{
    NSMutableString *str = [NSMutableString string];
    _OFCharacterDataFromElement(element, str);
    return str;
}

