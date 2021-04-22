// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFASCIIPropertyListSerialization.h>

#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFDataBuffer.h>
#import <OmniFoundation/OFErrors.h>

@protocol OFASCIIPropertyListSerializable
- (BOOL)OF_writeASCIIPropertyListToBuffer:(OFDataBuffer *)outputBuffer indent:(NSUInteger)indent error:(out NSError **)outError;
@end

@implementation OFASCIIPropertyListSerialization

static void _addIndent(OFDataBuffer *outputBuffer, NSUInteger indent)
{
    while (indent--) {
        OFDataBufferAppendCString(outputBuffer, "    ");
    }
}

static BOOL _writePropertyList(OFDataBuffer *outputBuffer, id plist, NSUInteger indent, NSError **outError)
{
    NSString *reason = [NSString stringWithFormat:@"Unable to archive a property list containing class %@ (content=%@)", [plist class], plist];
    if (![plist conformsToProtocol:@protocol(OFASCIIPropertyListSerializable)]) {
        OFError(outError, OFASCIIPropertyListSerializationUnsupportedContent, @"Unable to archive property list", reason);
        return NO;
    }
    return [plist OF_writeASCIIPropertyListToBuffer:outputBuffer indent:indent error:outError];
}

+ (nullable NSData *)dataFromPropertyList:(id)plist error:(out NSError **)outError;
{
    OFDataBuffer outputBuffer;
    OFDataBufferInit(&outputBuffer);
    if (!_writePropertyList(&outputBuffer, plist, 0, outError)) {
        OFDataBufferRelease(&outputBuffer, NULL, NULL);
        return nil;
    }

    CFDataRef resultData = NULL;
    OFDataBufferRelease(&outputBuffer, NULL, &resultData);
    return (NSData *)CFBridgingRelease(resultData);
}

+ (nullable NSString *)stringFromPropertyList:(id)plist error:(out NSError **)outError;
{
    NSData *data = [self dataFromPropertyList:plist error:outError];
    if (data == nil)
        return nil;
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return string;
}

@end

// Old-style ASCII property lists only support four classes: NSString, NSData, NSArray, and NSDictionary

@interface NSString (OFASCIIPropertyListSerialization) <OFASCIIPropertyListSerializable>
@end
@interface NSData (OFASCIIPropertyListSerialization) <OFASCIIPropertyListSerializable>
@end
@interface NSArray (OFASCIIPropertyListSerialization) <OFASCIIPropertyListSerializable>
@end
@interface NSDictionary (OFASCIIPropertyListSerialization) <OFASCIIPropertyListSerializable>
@end

@implementation NSString (OFASCIIPropertyListSerialization)

- (BOOL)OF_writeASCIIPropertyListToBuffer:(OFDataBuffer *)outputBuffer indent:(NSUInteger)indent error:(out NSError **)outError;
{
    if (OFIsEmptyString(self)) {
        // If we're asked to write an empty string, write ""
        OFDataBufferAppendCString(outputBuffer, "\"\"");
        return YES;
    }

    static NSCharacterSet *requiresQuotingCharacterSet = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *unquotedCharacters = [NSMutableCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"];
        [unquotedCharacters invert];
        requiresQuotingCharacterSet = [unquotedCharacters copy];
    });

    if ([self rangeOfCharacterFromSet:requiresQuotingCharacterSet].location == NSNotFound) {
        // This string contains only alphanumeric characters; it doesn't require quoting
        OFDataBufferAppendString(outputBuffer, (__bridge CFStringRef)self, kCFStringEncodingASCII);
        return YES;
    }

    OFDataBufferAppendByte(outputBuffer, '"');

    NSUInteger charCount = [self length];
    CFStringInlineBuffer charBuffer;
    CFStringInitInlineBuffer((CFStringRef)self, &charBuffer, CFRangeMake(0, charCount));

    for (NSUInteger charIndex = 0; charIndex < charCount; charIndex++) {
        unichar c = CFStringGetCharacterFromInlineBuffer(&charBuffer, charIndex);

        if (c == '\n') {
            OFDataBufferAppendCString(outputBuffer, "\\n");
        } else if (c == '"') {
            OFDataBufferAppendCString(outputBuffer, "\\\"");
        } else if (c == '\\') {
            OFDataBufferAppendCString(outputBuffer, "\\\\");
        } else if (c == '\t') {
            OFDataBufferAppendCString(outputBuffer, "\\t");
        } else if (isascii(c)) {
            OFDataBufferAppendByte(outputBuffer, (OFByte)c);
        } else {
            OFDataBufferAppendCString(outputBuffer, "\\U");
            OFDataBufferAppendHexForByte(outputBuffer, (c >> 8) & 0xff);
            OFDataBufferAppendHexForByte(outputBuffer, (c >> 0) & 0xff);
        }
    }

    OFDataBufferAppendByte(outputBuffer, '"');

    return YES;
}

@end

@implementation NSData (OFASCIIPropertyListSerialization)

- (BOOL)OF_writeASCIIPropertyListToBuffer:(OFDataBuffer *)outputBuffer indent:(NSUInteger)indent error:(out NSError **)outError;
{
    OFDataBufferAppendCString(outputBuffer, "<");

    const OFByte *bytes = [self bytes];
    NSUInteger length = [self length];

    while (length > 4) {
        OFDataBufferAppendHexWithReturnsForBytes(outputBuffer, bytes, 4);
        bytes += 4;
        length -= 4;

        if (length != 0) {
            OFDataBufferAppendByte(outputBuffer, ' ');
        }
    }
    if (length > 0) {
        OFDataBufferAppendHexWithReturnsForBytes(outputBuffer, bytes, length);
    }

    OFDataBufferAppendCString(outputBuffer, ">");
    return YES;
}

@end

@implementation NSArray (OFASCIIPropertyListSerialization)

- (BOOL)OF_writeASCIIPropertyListToBuffer:(OFDataBuffer *)outputBuffer indent:(NSUInteger)indent error:(out NSError **)outError;
{
    _addIndent(outputBuffer, indent); // This seems like a bug in the original plist emitter, since it adds space before sub-array values
    OFDataBufferAppendCString(outputBuffer, "(");

    BOOL needsDelimiter = NO;
    
    for (id item in self) {
        if (needsDelimiter) {
            OFDataBufferAppendCString(outputBuffer, ",");
        }
        OFDataBufferAppendCString(outputBuffer, "\n");
        _addIndent(outputBuffer, indent+1);

        if (!_writePropertyList(outputBuffer, item, indent+1, outError)) {
            return NO;
        }
        needsDelimiter = YES;
    }
    
    OFDataBufferAppendCString(outputBuffer, "\n");
    _addIndent(outputBuffer, indent);
    OFDataBufferAppendCString(outputBuffer, ")");
    return YES;
}

@end

@implementation NSDictionary (OFASCIIPropertyListSerialization)

- (BOOL)OF_writeASCIIPropertyListToBuffer:(OFDataBuffer *)outputBuffer indent:(NSUInteger)indent error:(out NSError **)outError;
{
    _addIndent(outputBuffer, indent); // This seems like a bug in the original plist emitter, since it adds space before sub-dictionary values
    OFDataBufferAppendCString(outputBuffer, "{");

    NSArray *sortedKeys = [[self allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (id key in sortedKeys) {
        id value = self[key];

        OFDataBufferAppendCString(outputBuffer, "\n");

        _addIndent(outputBuffer, indent+1);
        if (!_writePropertyList(outputBuffer, key, indent+1, outError)) {
            return NO;
        }
        OFDataBufferAppendCString(outputBuffer, " = ");
        if (!_writePropertyList(outputBuffer, value, indent+1, outError)) {
            return NO;
        }
        OFDataBufferAppendCString(outputBuffer, ";");
    }
    
    OFDataBufferAppendCString(outputBuffer, "\n");
    _addIndent(outputBuffer, indent);
    OFDataBufferAppendCString(outputBuffer, "}");
    return YES;
}

@end

// It's not uncommon to find an NSNumber in a plist, especially since they are treated as an independent type in XML and binary plists. We'll archive these as NSStrings.

@interface NSNumber (OFASCIIPropertyListSerialization) <OFASCIIPropertyListSerializable>
@end

@implementation NSNumber (OFASCIIPropertyListSerialization)

- (BOOL)OF_writeASCIIPropertyListToBuffer:(OFDataBuffer *)outputBuffer indent:(NSUInteger)indent error:(out NSError **)outError;
{
    return [[self description] OF_writeASCIIPropertyListToBuffer:outputBuffer indent:indent error:outError];
}

@end
