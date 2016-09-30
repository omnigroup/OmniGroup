// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWHTMLToSGMLObjects.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/NSString-OWSGMLString.h>
#import <OWF/OWContent.h>
#import <OWF/OWSGMLTag.h>
#import <OWF/OWSGMLTagType.h>
#import <OWF/OWSGMLAttribute.h>
#import <OWF/OWSGMLDTD.h>
#import <OWF/OWObjectStream.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWDataStreamCursor.h>
#import <OWF/OWDataStreamCharacterCursor.h>
#import <OWF/OWDataStreamCharacterProcessor.h>
#import <OWF/OWDataStreamScanner.h>
#import <OWF/OWParameterizedContentType.h>
#import <OWF/OWPipeline.h>

RCS_ID("$Id$")

@interface OWDataStreamScanner (OWHTMLScanning)
- (NSString *)_readFragmentUpToLeftAngleBracketOrAmpersand;
@end

@interface OWHTMLToSGMLObjects (Private)
+ (void)_decodeEntriesFromCharacterDictionary:(NSDictionary *)characterDictionary intoStringDictionary:(NSMutableDictionary *)stringDictionary;
+ (NSDictionary *)_invertEntitiesFromDictionary:(NSDictionary *)dictionary;
- (void)_initStreams;
- (void)_objectStreamIsValid;
- (void)_scanContent;
- (void)_scanTag;
- (void)_scanBeginTag;
- (NSString *)_readValueWithDelimiterOFCharacterSet:(OFCharacterSet *)delimiterOFCharacterSet newlinesAreDelimiters:(BOOL)newlinesAreDelimiters;
- (void)_scanEndTag;
- (void)_scanMarkupDeclaration;
- (void)_scanComment;
- (void)_scanProcessingInstruction;
- (id <OWSGMLToken>)_readEntity;
- (id <OWSGMLToken>)_readCharacterReference;
- (id <OWSGMLToken>)_readEntityReference;
- (unsigned int)_readNumber;
- (unsigned int)_readHexNumber;
- (void)_skipToEndOfTag;
- (void)_scanNonSGMLContent:(OWSGMLTag *)nonSGMLTag;
- (void)_metaCharsetTagHack:(OWSGMLTag *)tag;
- (void)_updateCharacterSetEncoding:(CFStringEncoding)newEncoding;
@end

static NSString *OWHTMLToSGMLObjectsCharacterEncodingResetExceptionName = @"OWHTMLToSGMLObjects character encoding reset";
static NSString *OWHTMLToSGMLObjectsCharacterEncodingResetExceptionKey = @"OWHTMLToSGMLObjects character encoding to use";

@implementation OWHTMLToSGMLObjects

// static Class stringDecoderClass;

NSLock *decoderDefaultsLock = nil;
 
static NSDictionary *entityDictionary;
static NSMutableDictionary *basicStringEntityDictionary;
static NSMutableDictionary *extendedStringEntityDictionary;
static NSDictionary *entityNameDictionary;

// bitmaps

static OFCharacterSet *CREFOFCharacterSet;
static OFCharacterSet *CommentEndOFCharacterSet;
static OFCharacterSet *DigitOFCharacterSet;
static OFCharacterSet *EndQuotedValueOFCharacterSet;
static OFCharacterSet *EndSingleQuotedValueOFCharacterSet;
static OFCharacterSet *EndTagOFCharacterSet;
static OFCharacterSet *EndValueOFCharacterSet;
static OFCharacterSet *InvertedBlankSpaceOFCharacterSet;
static OFCharacterSet *InvertedDigitOFCharacterSet;
static OFCharacterSet *InvertedHexDigitOFCharacterSet;
static OFCharacterSet *InvertedNameOFCharacterSet;
static OFCharacterSet *NameStartOFCharacterSet;
static OFCharacterSet *TagEndOrNameStartOFCharacterSet;

+ (void)initialize;
{
    OBINITIALIZE;
    
    @autoreleasepool {
        [self _initializeCharacterSets];
    }
}

+ (void)_initializeCharacterSets;
{
    // abstract syntax

    NSCharacterSet *DigitSet;
    NSCharacterSet *InvertedDigitSet;
    NSMutableCharacterSet *InvertedHexDigitSet;
    NSCharacterSet *LCLetterSet;
    NSCharacterSet *UCLetterSet;
    // NSCharacterSet *SpecialSet;

    // concrete syntax

    NSCharacterSet *LCNameCharSet;
    NSCharacterSet *RecordEndSet;
    NSCharacterSet *RecordStartSet;
    NSCharacterSet *SepCharSet;
    NSCharacterSet *SpaceSet;
    NSCharacterSet *UCNameCharSet;

    // categories

    NSMutableCharacterSet *NameStartCharacterSet;
    NSMutableCharacterSet *InvertedNameCharacterSet;
    NSMutableCharacterSet *BlankSpaceSet;
    NSCharacterSet *InvertedBlankSpaceSet;
    NSMutableCharacterSet *CREFSet;

    // made up

    NSCharacterSet *CommentEndSet;
    // NSCharacterSet *ContentEndSet;
    NSCharacterSet *EndQuotedValueSet;
    NSCharacterSet *EndSingleQuotedValueSet;
    NSMutableCharacterSet *EndValueSet;
    NSMutableCharacterSet *TagEndOrNameStartCharacterSet;

    entityDictionary = [[NSDictionary alloc] initWithContentsOfFile:[[OWHTMLToSGMLObjects bundle] pathForResource:@"entities" ofType:@"plist"]];
    basicStringEntityDictionary = [[entityDictionary objectForKey:@"strings"] mutableCopy];
    [self _decodeEntriesFromCharacterDictionary:[entityDictionary objectForKey:@"character"] intoStringDictionary:basicStringEntityDictionary];
    entityNameDictionary = [self _invertEntitiesFromDictionary:basicStringEntityDictionary];
    extendedStringEntityDictionary = [[NSMutableDictionary alloc] initWithDictionary:basicStringEntityDictionary];
    [self _decodeEntriesFromCharacterDictionary:[entityDictionary objectForKey:@"extendedCharacter"] intoStringDictionary:extendedStringEntityDictionary];
    
    if (decoderDefaultsLock == nil)
        decoderDefaultsLock = [[NSLock alloc] init];

// abstract syntax

    DigitSet = [NSCharacterSet decimalDigitCharacterSet];
    InvertedDigitSet = [DigitSet invertedSet];

    InvertedHexDigitSet = [[NSMutableCharacterSet alloc] init];
    [InvertedHexDigitSet formUnionWithCharacterSet:DigitSet];
    [InvertedHexDigitSet addCharactersInString:@"abcdefABCDEF"];
    [InvertedHexDigitSet invert];
    
    LCLetterSet = [NSCharacterSet lowercaseLetterCharacterSet];
    UCLetterSet = [NSCharacterSet uppercaseLetterCharacterSet];
    // SpecialSet = [NSCharacterSet characterSetWithCharactersInString:@"'()+,-./:=?"];

// concrete syntax

    LCNameCharSet = [NSCharacterSet characterSetWithCharactersInString:@"-."];
    RecordEndSet = [NSCharacterSet characterSetWithCharactersInString:@"\n"];
    RecordStartSet = [NSCharacterSet characterSetWithCharactersInString:@"\r"];
    SepCharSet = [NSCharacterSet characterSetWithCharactersInString:@"\t"];
    SpaceSet = [NSCharacterSet characterSetWithCharactersInString:@" "];
    UCNameCharSet = [NSCharacterSet characterSetWithCharactersInString:@"-."];

// categories

    NameStartCharacterSet = [[NSMutableCharacterSet alloc] init];
    [NameStartCharacterSet formUnionWithCharacterSet:LCLetterSet];
    [NameStartCharacterSet formUnionWithCharacterSet:UCLetterSet];

    InvertedNameCharacterSet = [[NSMutableCharacterSet alloc] init];
    [InvertedNameCharacterSet formUnionWithCharacterSet:NameStartCharacterSet];
    [InvertedNameCharacterSet formUnionWithCharacterSet:DigitSet];
    [InvertedNameCharacterSet formUnionWithCharacterSet:LCNameCharSet];
    [InvertedNameCharacterSet formUnionWithCharacterSet:UCNameCharSet];
    [InvertedNameCharacterSet invert];

    BlankSpaceSet = [[NSMutableCharacterSet alloc] init];
    [BlankSpaceSet formUnionWithCharacterSet:SpaceSet];
    [BlankSpaceSet formUnionWithCharacterSet:RecordEndSet];
    [BlankSpaceSet formUnionWithCharacterSet:RecordStartSet];
    [BlankSpaceSet formUnionWithCharacterSet:SepCharSet];

    InvertedBlankSpaceSet = [BlankSpaceSet invertedSet];

    CREFSet = [[NSMutableCharacterSet alloc] init];
    [CREFSet formUnionWithCharacterSet:DigitSet];
    [CREFSet addCharactersInString:@"xX"]; // SGML allows others, HTML does not

// made up

    CommentEndSet = [NSCharacterSet characterSetWithCharactersInString:@"-"];
    // ContentEndSet = [NSCharacterSet characterSetWithCharactersInString:@"<&"];
    EndQuotedValueSet = [NSCharacterSet characterSetWithCharactersInString:@"&\"\r\n"];
    EndSingleQuotedValueSet = [NSCharacterSet characterSetWithCharactersInString:@"&'\r\n"];

    EndValueSet = [BlankSpaceSet mutableCopy];
    [EndValueSet addCharactersInString:@"&>"];

    TagEndOrNameStartCharacterSet = [NameStartCharacterSet mutableCopy];
    [TagEndOrNameStartCharacterSet addCharactersInString:@">"];

    // Setup bitmaps
    CommentEndOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:CommentEndSet];
    CREFOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:CREFSet];
    DigitOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:DigitSet];
    EndQuotedValueOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:EndQuotedValueSet];
    EndSingleQuotedValueOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:EndSingleQuotedValueSet];
    EndTagOFCharacterSet = [[OFCharacterSet alloc] initWithString:@">'\""];
    EndValueOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:EndValueSet];
    InvertedBlankSpaceOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:InvertedBlankSpaceSet];
    InvertedDigitOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:InvertedDigitSet];
    InvertedHexDigitOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:InvertedHexDigitSet];
    InvertedNameOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:InvertedNameCharacterSet];
    NameStartOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:NameStartCharacterSet];
    TagEndOrNameStartOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:TagEndOrNameStartCharacterSet];
}

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description;
{
    // Register entity lists here
}

+ (BOOL)recognizesEntityNamed:(NSString *)entityName;
{
    return [extendedStringEntityDictionary objectForKey:entityName] != nil;
}

+ (NSString *)entityNameForCharacter:(unichar)character;
{
    // TODO someday: use a map table here instead of requiring us to create these temporary 1-character strings?
    NSString *key = [[NSString alloc] initWithCharacters:&character length:1];
    NSString *name = [entityNameDictionary objectForKey:key];
    return name;
}

// Init and dealloc

- initWithContent:(OWContent *)initialContent context:(id <OWProcessorContext>)aPipeline;
{
    self = [super initWithContent:initialContent context:aPipeline];
    if (self == nil)
        return nil;
        
    sourceContentDTD = [OWSGMLDTD dtdForSourceContentType:[initialContent contentType]];

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    flags.netscapeCompatibleComments = [userDefaults boolForKey:@"OWHTMLNetscapeCompatibleComments"];
    flags.netscapeCompatibleNewlineAfterEntity = [userDefaults boolForKey:@"OWHTMLNetscapeCompatibleNewlineAfterEntity"];
    flags.netscapeCompatibleNonterminatedEntities = [userDefaults boolForKey:@"OWHTMLNetscapeCompatibleNonterminatedEntities"];
    flags.shouldObeyMetaTag = [userDefaults boolForKey:@"OWHTMLCharsetInMetaTag"];

    if (flags.shouldObeyMetaTag) {
        NSNumber *sourceEncodingProvenance = [initialContent lastObjectForKey:OWContentEncodingProvenanceMetadataKey];
        if (sourceEncodingProvenance && [sourceEncodingProvenance intValue] >= OWStringEncodingProvenance_MetaTag)
            flags.shouldObeyMetaTag = NO;
    }

    tagTrie = [sourceContentDTD tagTrie];
        
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION([objectStream endOfData]);
    // The preceeding assertion fails on occasion, which is a bug.  For now, let's ensure that the consequences of the bug aren't too serious by making sure whoever reads our object stream doesn't hang forever (in a non-abortable state) waiting for our end of data signal.
    if (![objectStream endOfData])
        [objectStream dataAbort];
}

// OWProcessor subclass

- (void)processBegin
{
    resetSourceEncoding = kCFStringEncodingInvalidId;
    [super processBegin];
    [self _initStreams];
}

- (void)process;
{
    for (;;) {
        BOOL restart = NO;
        
        NS_DURING {
            [self _scanContent];
        } NS_HANDLER {
            if ([[localException name] isEqualToString:OWHTMLToSGMLObjectsCharacterEncodingResetExceptionName]) {
                restart = YES;
                resetSourceEncoding = [[[localException userInfo] objectForKey:OWHTMLToSGMLObjectsCharacterEncodingResetExceptionKey] unsignedIntValue];
            } else
                [localException raise];
        } NS_ENDHANDLER;
        
        if (restart)
            [self _initStreams];
        else
            break;
    }
    
    [objectStream dataEnd];
    [self _objectStreamIsValid];
}

- (void)processAbort;
{
    [objectStream dataAbort];
    [super processAbort];
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    if (objectStream != nil)
	[debugDictionary setObject:objectStream forKey:@"objectStream"];
    if (scanner != nil)
	[debugDictionary setObject:scanner forKey:@"scanner"];
    return debugDictionary;
}

@end

@implementation OWHTMLToSGMLObjects (Private)

#ifdef DEBUG
static BOOL OWHTMLToSGMLObjectsDebug = NO;

+ (void)setDebug:(BOOL)newDebug;
{
    OWHTMLToSGMLObjectsDebug = newDebug;
}
#endif

+ (void)_decodeEntriesFromCharacterDictionary:(NSDictionary *)characterDictionary intoStringDictionary:(NSMutableDictionary *)stringDictionary;
{
    NSEnumerator *characterKeyEnumerator;
    NSString *name;

    characterKeyEnumerator = [characterDictionary keyEnumerator];
    while ((name = [characterKeyEnumerator nextObject])) {
        NSString *encodedCharacterString, *characterString;
        UnicodeScalarValue character;
        encodedCharacterString = [characterDictionary objectForKey:name];
        character = [encodedCharacterString intValue];
        characterString = [NSString stringWithCharacter:character];
        [stringDictionary setObject:characterString forKey:name];
    }
}

+ (NSDictionary *)_invertEntitiesFromDictionary:(NSDictionary *)dictionary;
{
    NSMutableDictionary *inverseEntities = [[NSMutableDictionary alloc] initWithCapacity:[dictionary count]];
    NSEnumerator *characterKeyEnumerator = [dictionary keyEnumerator];
    for (NSString *name in characterKeyEnumerator) {
        NSString *characterString = [dictionary objectForKey:name];
        if ([characterString length] == 1)
            [inverseEntities setObject:name forKey:characterString];
    }
    NSDictionary *immutableResult = [[NSDictionary alloc] initWithDictionary:inverseEntities];

    return immutableResult;
}

- (void)_initStreams
{
    OBPRECONDITION(!flags.haveAddedObjectStreamToPipeline);

    BOOL restarting = ( resetSourceEncoding != kCFStringEncodingInvalidId );

#ifdef DEBUG
    if (OWHTMLToSGMLObjectsDebug)
        NSLog(@"%@ - creating object stream, restart=%@, resetEncoding=%ld",
              [self shortDescription], restarting?@"YES":@"NO", (long)resetSourceEncoding);
#endif
    
    if (restarting) {
        objectStream = nil;
        scanner = nil;
        
        OWDataStreamCursor *dataCursor = [characterCursor dataStreamCursor];
        characterCursor = nil;
        [dataCursor seekToOffset:0 fromPosition:OWCursorSeekFromStart];
        characterCursor = [[OWDataStreamCharacterCursor alloc] initForDataCursor:dataCursor encoding:resetSourceEncoding];
    }
    
    objectStream = [[OWObjectStream alloc] init];
    scanner = [[OWDataStreamScanner alloc] initWithCursor:characterCursor];
    
    if (flags.shouldObeyMetaTag) {
        // these aren't retained because they're never deallocated
        metaCharsetHackTagType = [sourceContentDTD tagTypeNamed:@"meta"];
        endMetaCharsetHackTagType = [sourceContentDTD tagTypeNamed:@"body"];
    } else {
        metaCharsetHackTagType = nil;
        endMetaCharsetHackTagType = nil;

        [self _objectStreamIsValid];
    }

}

- (void)_scanContent;
{
    if (scanner == nil)
	return;

    while (scannerHasData(scanner)) {
        switch (scannerPeekCharacter(scanner)) {
            case '<':
                scannerSkipPeekedCharacter(scanner);
                [self _scanTag];
                break;
            case '&':
                scannerSkipPeekedCharacter(scanner);
                [objectStream writeObject:[self _readEntity]];
                break;
            default:
                [objectStream writeObject:[scanner _readFragmentUpToLeftAngleBracketOrAmpersand]];
                break;
        }
    }
}

- (void)_scanTag;
{
    unichar peekCharacter;

    switch ((peekCharacter = scannerPeekCharacter(scanner))) {
        case '/':
            scannerSkipPeekedCharacter(scanner);
            [self _scanEndTag];
            break;
        case '!':
            scannerSkipPeekedCharacter(scanner);
            [self _scanMarkupDeclaration];
            break;
        case '?':
            scannerSkipPeekedCharacter(scanner);
            [self _scanProcessingInstruction];
            break;
        default:
            if (OFCharacterSetHasMember(NameStartOFCharacterSet, peekCharacter))
                [self _scanBeginTag];
            else
                [objectStream writeObject:@"<"];
            break;
    }
}

- (void)_scanBeginTag;
{
    OWSGMLTagType *tagType = (OWSGMLTagType *)[scanner readLongestTrieElement:tagTrie];
    if (!tagType || !OFCharacterSetHasMember(InvertedNameOFCharacterSet, scannerPeekCharacter(scanner))) {
	[self _skipToEndOfTag];
	return;
    }

    
    OWSGMLTag *tag = nil;
    OFTrie *attributeTrie = [tagType attributeTrie];
    
    while (scannerHasData(scanner)) {
        NSString *extraAttributeName = nil;
        NSString *value;

        scannerScanUpToCharacterInOFCharacterSet(scanner, TagEndOrNameStartOFCharacterSet);
        if (scannerPeekCharacter(scanner) == '>') {
            scannerSkipPeekedCharacter(scanner);
            break;
        }
                           
        [scanner setRewindMark];
        OWSGMLAttribute *attribute = (OWSGMLAttribute *)[scanner readLongestTrieElement:attributeTrie];
        if (attribute && !OFCharacterSetHasMember(InvertedNameOFCharacterSet, scannerPeekCharacter(scanner))) {
            // The attribute name starts with a value we recognize, but has more text afterwards. Back up and read it from the start.
            attribute = nil;
            [scanner rewindToMark];
        } else {
            [scanner discardRewindMark];
        }
        
        if (!attribute)
            extraAttributeName = [scanner readFullTokenWithDelimiterOFCharacterSet:InvertedNameOFCharacterSet];

        scannerScanUpToCharacterInOFCharacterSet(scanner, InvertedBlankSpaceOFCharacterSet);
        if (scannerPeekCharacter(scanner) == '=') {
            unichar character;
            
            scannerSkipPeekedCharacter(scanner);
            scannerScanUpToCharacterInOFCharacterSet(scanner, InvertedBlankSpaceOFCharacterSet);
            
            switch ((character = scannerPeekCharacter(scanner))) {
                case '"':
                case '\'':
                    scannerSkipPeekedCharacter(scanner);
                    value = [self _readValueWithDelimiterOFCharacterSet:(character == '"' ? EndQuotedValueOFCharacterSet : EndSingleQuotedValueOFCharacterSet) newlinesAreDelimiters:NO];
                    if (scannerPeekCharacter(scanner) != '>')
                        scannerSkipPeekedCharacter(scanner);
                        break;
                default:
                    value = [self _readValueWithDelimiterOFCharacterSet:EndValueOFCharacterSet newlinesAreDelimiters:YES];
                    break;
            }
        } else {
            value = [OFNull nullStringObject];
        }
        
        if (attribute || (extraAttributeName && value)) {
            if (tag == nil) {
                tag = [OWSGMLTag newTagWithTokenType:OWSGMLTokenTypeStartTag tagType:tagType];
            }
            
            if (attribute)
                [tag setValue:value atIndex:[attribute offset]];
            else
                [tag setValue:value forExtraAttribute:extraAttributeName];
        }
    }

    if (tag == nil)
        tag = [tagType attributelessStartTag];
    
    [objectStream writeObject:tag];
#ifdef DEBUG
    if (OWHTMLToSGMLObjectsDebug)
        NSLog(@"Tag: %@", tag);
#endif
    
    // Ugly hack to support non-SGML tags such as <SCRIPT> and stylesheets
    if ([tagType contentHandling] != OWSGMLTagContentHandlingNormal)
        [self _scanNonSGMLContent:tag];
    
    // Ugly hack to support changing charsets in mid-stream
    if (tagType == metaCharsetHackTagType) {
        [self _metaCharsetTagHack:tag];
    } else if (tagType == endMetaCharsetHackTagType) {
        metaCharsetHackTagType = nil;
        endMetaCharsetHackTagType = nil;
        [self _objectStreamIsValid];
    }
}

- (void)_objectStreamIsValid
{
    // This is called after we know that we are not going to be restarting with a new string encoding (and a new object stream). Before that point, it's possible we'll be throwing away the object stream and starting over, so we can't add it to the pipeline yet.
    
    if (flags.haveAddedObjectStreamToPipeline)
        return;

    CFStringEncoding sourceEncoding = [[scanner dataStreamCursor] stringEncoding];

    OWContent *resultContent = [[OWContent alloc] initWithName:nil content:objectStream];
    [resultContent setContentType:[sourceContentDTD destinationType]];
    
    if (sourceEncoding != kCFStringEncodingInvalidId) {
        // Even though we are sending NSStrings downstream, some later processors might want to know the string encoding of the original document, e.g. forms want to encode their responses in the same character set as the document they came from.
        [resultContent addHeader:OWContentSourceEncodingMetadataKey value:[NSNumber numberWithUnsignedInt:sourceEncoding]];
    }
    
    [resultContent markEndOfHeaders];
    
    [self.pipeline addContent:resultContent fromProcessor:self flags:OWProcessorTypeDerived];
    
    flags.haveAddedObjectStreamToPipeline = 1;
}

- (void)_metaCharsetTagHack:(OWSGMLTag *)tag;
{
    // We shouldn't have already added the object stream to the pipeline, because the point of delaying adding the object stream to the pipeline is to allow us to change charsets due to a META tag.
    OBASSERT(!flags.haveAddedObjectStreamToPipeline);

    NSString *httpEquivalentValue = [tag valueForAttribute:@"http-equiv"];
    if (httpEquivalentValue != nil && [httpEquivalentValue caseInsensitiveCompare:@"content-type"] == NSOrderedSame)  {
        // <meta http-equiv=content-type content="text/html; charset=iso-8859-1">
        NSString *newContentTypeString = [tag valueForAttribute:@"content"];
        if (newContentTypeString == nil)
            return; // Ignore tag: no content attribute value
        OWParameterizedContentType *newContentType = [OWParameterizedContentType contentTypeForString:[tag valueForAttribute:@"content"]];
        if (newContentType == nil)
            return; // Ignore tag: content type failed to parse
        [self _updateCharacterSetEncoding:[OWDataStreamCharacterProcessor stringEncodingForContentType:newContentType]];
        return;
    }
    NSString *charsetValue = [tag valueForAttribute:@"charset"];
    if (charsetValue != nil) {
        // <meta charset="iso-8859-1"> is a Microsoft IE extension
        [self _updateCharacterSetEncoding:[OWDataStreamCharacterProcessor stringEncodingForIANACharSetName:charsetValue]];
        return;
    }
}

- (void)_updateCharacterSetEncoding:(CFStringEncoding)newEncoding;
{
    CFStringEncoding currentEncoding;

    if (newEncoding == kCFStringEncodingInvalidId)
            return; // Ignore change:  unrecognized encoding or no encoding specified

    // Store the changed content type in the dataStream. This is a little unsatisfactory since it means that if the data stream is processed again from the cache, it'll get the new encoding; but we don't really have a better place to stash this information so that the source view can still find it. (Maybe we should create a new content-type for charset hints, and store that in the cache alongside the data stream?)
    
    currentEncoding = [[scanner dataStreamCursor] stringEncoding];
    if ((newEncoding == kCFStringEncodingUnicode || currentEncoding == kCFStringEncodingUnicode) && newEncoding != currentEncoding) {
        // We shouldn't switch to or from UTF-16, because our ability to read this meta tag at all implies that it's written in an encoding which is compatible with ours for the set of base ASCII characters (which isn't true for UTF-16 and anything else).  In other words, it looks like the tag requested an encoding other than the one they're actually using.
        return;
    }
    
    if (newEncoding != currentEncoding) {
        NSException *reset = [NSException exceptionWithName:OWHTMLToSGMLObjectsCharacterEncodingResetExceptionName reason:@"(restart due to charset change)" userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:newEncoding] forKey:OWHTMLToSGMLObjectsCharacterEncodingResetExceptionKey]];
        [reset raise];
        // nb: the above exception is never seen by the user; it does not need to be localized.
    } else {
        // We've seen a charset override; we didn't do anything about it, but we're still not going to allow another one, because we're ornery sons of bitches who talk about our code in the first person plural.
        metaCharsetHackTagType = nil;
        endMetaCharsetHackTagType = nil;
        [self _objectStreamIsValid];
    }
}

- (NSString *)_readValueWithDelimiterOFCharacterSet:(OFCharacterSet *)delimiterOFCharacterSet newlinesAreDelimiters:(BOOL)newlinesAreDelimiters;
{
    NSMutableString *mergedValue;
    NSString *value;
    BOOL stillLooking = YES;

    mergedValue = [NSMutableString string];

    while (stillLooking) {
	id <OWSGMLToken> entityToken;
	unichar peekCharacter;
	    
	value = [scanner readFullTokenWithDelimiterOFCharacterSet:delimiterOFCharacterSet forceLowercase:NO];
	if (value)
	    [mergedValue appendString:value];

	peekCharacter = scannerPeekCharacter(scanner);
        switch (peekCharacter) {
            case '&':
                scannerSkipPeekedCharacter(scanner);
                entityToken = [self _readEntity];
                [mergedValue appendString:[entityToken string]];
                break;
            case '\r':
            case '\n':
                if (newlinesAreDelimiters) {
                    stillLooking = NO;
                    break;
                }

                // True SGML would have us replace these with whitespace, but all modern browsers just include the characters in the value string
                do {
                    [mergedValue appendString:[NSString stringWithCharacter:peekCharacter]];
                    scannerSkipPeekedCharacter(scanner);
                    peekCharacter = scannerPeekCharacter(scanner);
                } while (peekCharacter == '\r' || peekCharacter == '\n');
                break;
            default:
                stillLooking = NO;
                break;
        }
    }
    return mergedValue;
}

- (void)_scanEndTag;
{
    OWSGMLTagType *tagType;

    if (!OFCharacterSetHasMember(NameStartOFCharacterSet, scannerPeekCharacter(scanner))) {
        [objectStream writeObject:@"</"];
        return;
    }

    tagType = (OWSGMLTagType *)[scanner readLongestTrieElement:tagTrie];
    if (tagType && OFCharacterSetHasMember(InvertedNameOFCharacterSet, scannerPeekCharacter(scanner))) {
        [objectStream writeObject:[tagType attributelessEndTag]];
#ifdef DEBUG
        if (OWHTMLToSGMLObjectsDebug)
            NSLog(@"Tag: %@", [tagType attributelessEndTag]);
#endif
    }
    [self _skipToEndOfTag];
}

- (void)_scanMarkupDeclaration;
{
    unichar character;

    character = scannerReadCharacter(scanner);
    if (character == '>') {
	// Empty declaration! We're done.
    } else if (character == '-' && scannerPeekCharacter(scanner) == '-') {
	scannerSkipPeekedCharacter(scanner);
	[self _scanComment];
    } else if (character == 'D' && [[scanner readFullTokenWithDelimiterOFCharacterSet:InvertedNameOFCharacterSet] isEqualToString:@"OCTYPE"]) {
        //  a DOCTYPE declaration        
        NSString *type;
        
        [scanner setRewindMark];        
        [scanner readFullTokenWithDelimiterOFCharacterSet:EndTagOFCharacterSet]; // 'HTML PUBLIC' ignored
        if (scannerReadCharacter(scanner) == '>') {
            // no doctype at all. done.
            return;
        }
        type = [scanner readFullTokenWithDelimiterOFCharacterSet:EndTagOFCharacterSet];
        if ([type rangeOfString:@"Transitional"].length == 0) {
            // transitional isn't in the type, so be strict
            // Nobody uses this any more, so I'm commenting it out [wiml]
            // [pipeline addHeader:OWContentDoctypeMetadataKey value:@"HTML 4.0 Strict"];
        }
        if (scannerReadCharacter(scanner) == '>') {
            // no ending quote. oh well.
            return;
        }
        [scanner readFullTokenWithDelimiterOFCharacterSet:EndTagOFCharacterSet]; // skip blank between type and dtd
        if (scannerReadCharacter(scanner) == '>') {
            // no dtd.
            return;
        }
        
        // got a dtd, so go to strict mode...
        // Nobody uses this any more, so I'm commenting it out [wiml]
        // [pipeline addHeader:OWContentDoctypeMetadataKey value:@"HTML 4.0 Strict"];
        [scanner readFullTokenWithDelimiterOFCharacterSet:EndTagOFCharacterSet]; // skip dtd
        if (scannerReadCharacter(scanner) != '>')
            [self _skipToEndOfTag];
    } else if (flags.netscapeCompatibleComments || OFCharacterSetHasMember(NameStartOFCharacterSet, character)) {
	[self _skipToEndOfTag];
    } else {
	// Not markup after all!
	[scanner skipCharacters:-1];
	[objectStream writeObject:@"<!"];
    }
}

- (void)_scanComment;
{
    unichar character;

    [scanner setRewindMark];
    do {
        scannerScanUpToCharacterInOFCharacterSet(scanner, CommentEndOFCharacterSet);
	if (scannerReadCharacter(scanner) == '-' && scannerReadCharacter(scanner) == '-') {
	    while (scannerPeekCharacter(scanner) == '-')
		scannerSkipPeekedCharacter(scanner);
            scannerScanUpToCharacterInOFCharacterSet(scanner, InvertedBlankSpaceOFCharacterSet);
	    character = scannerPeekCharacter(scanner);
	    if (character == '>') {
                [scanner discardRewindMark];
		scannerSkipPeekedCharacter(scanner);
		return;
	    }
	}
    } while (scannerHasData(scanner));

    // Woops, not a proper SGML comment!  Let's try old-style HTML.
    [scanner rewindToMark];
    [self _skipToEndOfTag];
}

- (void)_scanProcessingInstruction; // ISO 8879 8
{
    if (scannerScanUpToCharacter(scanner, '>')) {
        scannerSkipPeekedCharacter(scanner);
    } else {
        // Not markup after all!
        [objectStream writeObject:@"<?"];
    }
}

- (id <OWSGMLToken>)_readEntity;
{
    unichar character;
    
    character = scannerPeekCharacter(scanner);
    switch (character) {
        case '#':
            scannerSkipPeekedCharacter(scanner);
            return [self _readCharacterReference];
        case '{': // JavaScript entity:  &{ ... };
            // See JavaScript: The Definitive Guide, section 10.5 (page 166)
            // We're not going to try to interpret this right now, but we'll at least try to make sure the embedded code doesn't interfere with our normal parsing
            [scanner setRewindMark];
            scannerSkipPeekedCharacter(scanner);
            while (scannerScanUpToCharacter(scanner, '}')) {
                scannerSkipPeekedCharacter(scanner);
                if (scannerPeekCharacter(scanner) == ';') {
                    // Found our terminator
                    NSUInteger terminatorScanLocation;
                    NSString *javaScriptCode;

                    terminatorScanLocation = [scanner scanLocation];
                    [scanner rewindToMark];
                    scannerSkipPeekedCharacter(scanner);
                    javaScriptCode = [scanner readCharacterCount:terminatorScanLocation - [scanner scanLocation] - 1];
                    scannerSkipPeekedCharacter(scanner); // '}'
                    scannerSkipPeekedCharacter(scanner); // ';'
                    return [NSString stringWithFormat:@"&{%@};", javaScriptCode]; // Actually, we should evaluate the string and return its return value
                }
            }
            // Huh!  No terminator, perhaps this wasn't a JavaScript entity after all.  Rewind, and parse normally.
            [scanner rewindToMark];
            // NO BREAK
        default:
            if (OFCharacterSetHasMember(NameStartOFCharacterSet, character))
                return [self _readEntityReference];
            else
                return @"&";
    }
}

- (id <OWSGMLToken>)_readCharacterReference;
{
    UnicodeScalarValue character = scannerPeekCharacter(scanner); // NB: UnicodeScalarValue is different from unichar
    if (!OFCharacterSetHasMember(CREFOFCharacterSet, character))
	return @"&#";
    if (OFCharacterSetHasMember(DigitOFCharacterSet, character)) {
	character = [self _readNumber];
    } else { // character is 'x'
        scannerSkipPeekedCharacter(scanner);
        character = [self _readHexNumber];
    }

    // WJS: 5/19/98 Even though the upper control characters aren't mapped in ISO Latin-1, they work in Netscape and Windows, so we check for that range explicitly and interpret them as WindowsCP1252 characters.
    // WIML July2000: Change this to use the new functions in OmniFoundation
    NSString *value = nil;
    if (character > 0x7e && character < 0xa0) {
        unsigned char byte = character & 0xff;
        NSData *data = [[NSData alloc] initWithBytes:&byte length:1];
        value = [NSString stringWithData:data encoding:NSWindowsCP1252StringEncoding];
    }
    if (value == nil)
        value = [NSString stringWithCharacter:character];

    character = scannerPeekCharacter(scanner);
    if (character == ';' || (!flags.netscapeCompatibleNewlineAfterEntity && character == '\n'))
	scannerSkipPeekedCharacter(scanner);
    OBPOSTCONDITION(value != nil);
    return value;
}

- (id <OWSGMLToken>)_readEntityReference;
{
    NSString *name = [scanner readFullTokenWithDelimiterOFCharacterSet:InvertedNameOFCharacterSet forceLowercase:NO];
    NSUInteger nameLength = name ? [name length] : 0;
    if (nameLength == 0)
        return @"&";

    unichar terminatingCharacter = scannerPeekCharacter(scanner);
    NSString *value;
    if (terminatingCharacter == ';')
        value = [extendedStringEntityDictionary objectForKey:name];
    else
        value = [basicStringEntityDictionary objectForKey:name];
    if (value != nil) {
        if (terminatingCharacter == ';' || (terminatingCharacter == '\n' && !flags.netscapeCompatibleNewlineAfterEntity))
            scannerSkipPeekedCharacter(scanner);
        return value;
    } else {
	if (flags.netscapeCompatibleNonterminatedEntities) {
	    NSUInteger tryLength;

	    for (tryLength = nameLength - 1; tryLength > 0; tryLength--) {
		value = [basicStringEntityDictionary objectForKey:[name substringToIndex:tryLength]];
		if (value) {
		    [scanner skipCharacters:-(int)(nameLength - tryLength)];
		    return value;
		}
	    }
	}
	return [NSString stringWithFormat:@"&%@", name];
    }
}

- (unsigned int)_readNumber;
{
    return [[scanner readFullTokenWithDelimiterOFCharacterSet:InvertedDigitOFCharacterSet forceLowercase:NO] intValue];
}

- (unsigned int)_readHexNumber;
{
    return [[scanner readFullTokenWithDelimiterOFCharacterSet:InvertedHexDigitOFCharacterSet forceLowercase:NO] hexValue];
}

- (void)_skipToEndOfTag;
{
    [scanner setRewindMark];
    for (;;) {
        unichar character;

        if (!scannerScanUpToCharacterInOFCharacterSet(scanner, EndTagOFCharacterSet))
            break; // abort

        character = scannerReadCharacter(scanner);
        switch (character) {
            case '>':
                [scanner discardRewindMark];
                return; // success
            default:
                // find matching quote
                if (scannerScanUpToCharacter(scanner, character))
                    scannerSkipPeekedCharacter(scanner);
                break;
        }
    }

    // Fine, I give up!
    [scanner rewindToMark];
}

- (void)_scanNonSGMLContent:(OWSGMLTag *)nonSGMLTag;
{
    while (scannerHasData(scanner)) {

        switch (scannerPeekCharacter(scanner)) {
            case '<':
                scannerSkipPeekedCharacter(scanner);
                
                if (scannerPeekCharacter(scanner) == '/') {
                    // end tag, but is it the end tag for this non-SGML block?
                    scannerSkipPeekedCharacter(scanner);
                    if ([scanner scanStringCaseInsensitive:[nonSGMLTag name] peek:YES]) {
                        [self _scanEndTag];
                        return;
                    } else {
                        [objectStream writeObject:@"</"];
                        break;
                    }
                    
                } else if ([scanner scanString:@"!--" peek:NO]) {
                    // start comment, so just write blindly until we hit end comment (this is what IE 5.1 does)
                    [objectStream writeObject:@"<!--"];
                    [objectStream writeObject:[scanner readFullTokenUpToString:@"-->"]];
                } else
                    [objectStream writeObject:@"<"];

                break;
            case '&':
                if ([[nonSGMLTag tagType] contentHandling] == OWSGMLTagContentHandlingNonSGMLWithEntities) {
                    scannerSkipPeekedCharacter(scanner);
                    [objectStream writeObject:[self _readEntity]];
                } else {
                    scannerSkipPeekedCharacter(scanner);
                    [objectStream writeObject:@"&"];
                }
                break;
            default:
                [objectStream writeObject:[scanner _readFragmentUpToLeftAngleBracketOrAmpersand]];
                break;
        }
    }
}

@end

@implementation OWDataStreamScanner (SpecialScanning)

- (NSString *)_readFragmentUpToLeftAngleBracketOrAmpersand;
{
    if (!scannerHasData(self))
        return nil;

    unichar *startLocation = scanLocation;
    while (scanLocation < scanEnd) {
        if (*scanLocation == '<' || *scanLocation == '&')
            break;
        scanLocation++;
    }

    return [NSString stringWithCharacters:startLocation length:scanLocation - startLocation];
}

@end
