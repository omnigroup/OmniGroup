// Copyright 2003-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWMultipartDataStreamProcessor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OWF/OWDataStream.h>
#import <OWF/OWDataStreamCursor.h>
#import <OWF/OWDataStreamCharacterCursor.h>
#import <OWF/OWHeaderDictionary.h>

RCS_ID("$Id$")

@implementation OWMultipartDataStreamProcessor

#define DEFAULT_INPUT_BUFFER_SIZE (8 * 1024)

static NSString *PartFormatString = nil;

+ (void)initialize;
{
    OBINITIALIZE;

    PartFormatString = NSLocalizedStringFromTableInBundle(@"Part %d...", @"OWF", OMNI_BUNDLE, @"mulitpart datastream processor status format");
}

- (void)dealloc;
{
    if (delimiter != NULL)
        free(delimiter);
}

- (BOOL)readDelimiter;
{
    NSString *line = nil;
    OWDataStreamCharacterCursor *lineScanner = [[OWDataStreamCharacterCursor alloc] initForDataCursor:dataCursor encoding:OFDeferredASCIISupersetStringEncoding];
    do {
        line = [lineScanner readLine];
    } while (line != nil && ![line hasPrefix:@"--"]);
    [lineScanner discardReadahead];
    if (line == nil)
	return NO;
    
    NSString *delimiterString = [@"\n" stringByAppendingString:line];
    delimiterLength = [delimiterString maximumLengthOfBytesUsingEncoding:NSMacOSRomanStringEncoding];
    delimiter = malloc(delimiterLength + 1);
    if (![delimiterString getCString:(char *)delimiter maxLength:delimiterLength + 1 encoding:NSMacOSRomanStringEncoding])
        [NSException raise:NSInternalInconsistencyException format:@"Failed to decode delimiter of multipart stream"];

    inputBufferSize = DEFAULT_INPUT_BUFFER_SIZE;
    if (delimiterLength * 2 > inputBufferSize)
	inputBufferSize = delimiterLength * 2;
    if (inputBufferSize % delimiterLength != 0)
	inputBufferSize += delimiterLength - inputBufferSize % delimiterLength;

    unsigned int characterIndex, delimiterIndex;
    for (characterIndex = 0; characterIndex < 256; characterIndex++)
	delimiterSkipTable[characterIndex] = delimiterLength;
    for (delimiterIndex = 0; delimiterIndex < delimiterLength; delimiterIndex++)
	delimiterSkipTable[delimiter[delimiterIndex]] = delimiterLength - delimiterIndex - 1;

    return YES;
}

- (void)processPartIntoStream:(OWDataStream *)outputDataStream;
{
    BOOL foundDelimiter = NO;
    unsigned char inputBuffer[inputBufferSize];
    unsigned char *currentCharacter;
    NSUInteger charactersRead, charactersToSkip, charactersToWrite;
    NSUInteger lastDelimiterCharacter = delimiterLength - 1;

    do {
	[dataCursor bufferBytes:delimiterLength];
	charactersRead = [dataCursor readMaximumBytes:inputBufferSize intoBuffer:inputBuffer];
// OmniLog(@"Read %d characters", charactersRead);
	currentCharacter = inputBuffer + lastDelimiterCharacter;
	while (currentCharacter < inputBuffer + charactersRead) {
	    charactersToSkip = delimiterSkipTable[*currentCharacter];
// OmniLog(@"currentCharacter = '%c', skipping %d", *currentCharacter, charactersToSkip);
	    if (charactersToSkip == 0) {
// OmniLog(@"strcmp('%s','%s')", currentCharacter - lastDelimiterCharacter, delimiter);
		if (strncmp((char *)currentCharacter - lastDelimiterCharacter, (char *)delimiter, delimiterLength) == 0) {
		    foundDelimiter = YES;
// OmniLog(@"Found delimiter!");
		    break;
		} else {
		    charactersToSkip = 1;
		}
	    }
	    currentCharacter += charactersToSkip;
	}
	charactersToWrite = currentCharacter - lastDelimiterCharacter - inputBuffer;
// OmniLog(@"Writing %d characters, skipping %d", charactersToWrite, charactersToWrite - charactersRead);
	[outputDataStream writeData:
	 [NSData dataWithBytes:inputBuffer length:charactersToWrite]];
	if (charactersToWrite - charactersRead != 0)
	    [dataCursor seekToOffset:charactersToWrite - charactersRead fromPosition:OWCursorSeekFromCurrent];
    } while (!foundDelimiter);
    [dataCursor skipBytes:delimiterLength];
    [dataCursor scanUpToByte:'\n'];
    [dataCursor skipBytes:1];  /* skip the \n we just scanned to */
}

- (void)processDataStreamPart:(OWDataStream *)aDataStream headers:(OWHeaderDictionary *)partHeaders;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)processContentWithHeaders:(OWHeaderDictionary *)partHeaders;
{
    OWDataStream *outputDataStream = [[OWDataStream alloc] init];
    @try {
        [self processDataStreamPart:outputDataStream headers:partHeaders];
	[self processPartIntoStream:outputDataStream];
    } @finally {
	/* Perhaps copy the rest of the input into the output */
        [outputDataStream dataEnd];
    }
}

// OWProcessor subclass

- (void)process;
{
    if (dataCursor == nil)
	return;
    if (![self readDelimiter])
	return;

    NSDate *nextDisplayDate = nil;
    unsigned int index = 0;
    
    @try {
	while (YES) {
            @autoreleasepool {
                OWHeaderDictionary *headerDictionary = [[OWHeaderDictionary alloc] init];
                [headerDictionary readRFC822HeadersFromCursor:dataCursor];
                [dataCursor bufferBytes:delimiterLength];
                NSString *durationHeader = [headerDictionary lastStringForKey:@"display-duration"];
                if (nextDisplayDate != nil) {
                    [nextDisplayDate sleepUntilDate];
                    nextDisplayDate = nil;
                }
                if (durationHeader != nil) {
                    nextDisplayDate = [[NSDate alloc] initWithTimeIntervalSinceNow:[durationHeader floatValue]];
                }
                [self setStatusString:[NSString stringWithFormat:PartFormatString, ++index]];
                [self processContentWithHeaders:headerDictionary];
            }
        }
    } @catch (NSException *exc) {
        OB_UNUSED_VALUE(exc);
    }
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    if (delimiter) {
	[debugDictionary setObject:[NSString stringWithUTF8String:(char *)delimiter] forKey:@"delimiter"];
	[debugDictionary setObject:[NSString stringWithFormat:@"%ld", delimiterLength] forKey:@"delimiterLength"];
    }
    return debugDictionary;
}

@end
