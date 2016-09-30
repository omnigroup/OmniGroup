// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWDataStreamScanner.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWDataStreamCharacterCursor.h>
#import <OWF/OWDataStream.h>

RCS_ID("$Id$")

@implementation OWDataStreamScanner

- initWithCursor:(OWDataStreamCharacterCursor *)aStreamCursor bufferLength:(unsigned int)aBufferLength;
{
    if (!(self = [super init]))
        return nil;

    streamCursor = aStreamCursor;
    
    minimumReadBufferLength = aBufferLength;
    if (minimumReadBufferLength < NSPageSize())
        minimumReadBufferLength = NSPageSize();
        // Setting the minimum read buffer length to NSPageSize means that we'll read at least one page's worth of 1-byte characters into our unichar buffer, in the common case where 1 byte --> 1 unichar.

    bufferSize = minimumReadBufferLength;
    buffer = (unichar *)malloc(MAX(bufferSize, 1UL) * sizeof(unichar));
    bufferLength = 0;
    bufferOffset = 0;
    
    return self;
}

- initWithCursor:(OWDataStreamCharacterCursor *)aStreamCursor;
{
    return [self initWithCursor:aStreamCursor bufferLength:0];
}

- (void)dealloc;
{
    free(buffer);
}

// OWScanner subclass

- (BOOL)fetchMoreData;
{
    NSUInteger desiredOffset = inputStringPosition + (scanLocation - inputBuffer);
    NSUInteger retainedCharacters, newBufferSize, charactersToRead, totalCharactersRead;
        
    if (desiredOffset < bufferOffset) {
        [NSException raise:OFCharacterConversionExceptionName format:@"Attempted backwards seek past rewind mark"];
    }
    
    if (desiredOffset < (bufferOffset + bufferLength)) {
        /* ??? we shouldn't be called in this case --- we have nothing to do */
        return YES;
    }
    
    // TODO: Note that in many cases, the underlying string encoding is "simple" and the character stream cursor could be made efficiently seekable. In that case, we should simply seek the cursor instead of doing all this buffering and copying. However, we will always need to have this logic somewhere so that we can scan strings in non-simple encodings (such as UTF8, ShiftJIS, etc.)
    
    // Figure out how much of the current buffer contents we need to keep around for rewinding purposes
    if (rewindMarkCount > 0 && bufferOffset + bufferLength > rewindMarkOffsets[0])
        retainedCharacters = (bufferOffset + bufferLength) - rewindMarkOffsets[0];
    else
        retainedCharacters = 0;

    if (retainedCharacters > 0) {
        NSUInteger discardedCharacters = bufferLength - retainedCharacters;
        
        OBASSERT(retainedCharacters <= bufferLength);
        if (discardedCharacters != 0) {
            // NB cannot use memcpy() here, as the strings may overlap
            memmove(buffer, buffer + discardedCharacters, retainedCharacters * sizeof(unichar));
#ifdef DEBUG_REWIND_BUFFER
            NSLog(@"OWDataStreamScanner: rewind-buffer copy overhead: %d characters", retainedCharacters);
#endif
        }
        bufferOffset = rewindMarkOffsets[0];
        bufferLength = retainedCharacters;
    } else {
        bufferOffset = bufferOffset + bufferLength;
        bufferLength = 0;
    }

    charactersToRead = MAX(minimumReadBufferLength, 1 + desiredOffset - (bufferOffset - bufferLength));
    newBufferSize = bufferLength + charactersToRead;
    
    if (newBufferSize > bufferSize || (newBufferSize < (bufferSize / 8))) {
        buffer = realloc(buffer, newBufferSize * sizeof(unichar));
        bufferSize = newBufferSize;
    }
    
    totalCharactersRead = 0;
    do {
        NSUInteger charactersRead;

        charactersRead = [streamCursor readCharactersIntoBuffer:(buffer + bufferLength) maximum:(bufferSize - bufferLength) peek:NO];
        totalCharactersRead += charactersRead;
        bufferLength += charactersRead;
    } while (totalCharactersRead < charactersToRead && ![streamCursor isAtEOF]);
    
    [self fetchMoreDataFromCharacters:buffer length:bufferLength offset:bufferOffset freeWhenDone:NO];

    return (totalCharactersRead > 0) ? YES : NO;
}

- (OWDataStreamCharacterCursor *)dataStreamCursor;
{
    return streamCursor;
}

// NB: Arguably, some of this functionality should be in the superclass. The superclass' definition could call _rewindCharacterSource and most of this method's functionality could be moved into an overridden version of that one. However, _rewindCharacterSource's semantics would have to be thought out a little more, since right now it's also used for actual seeks (which always fail). The tricky part would be making sure that an unseekable dataStream raises an exception early enough that the scanner is left in a consistent state.
- (void)discardReadahead;
{
    // NB: It's important that any exceptions raised in this method leave the scanner in a consistent state, with the scan location unchanged!

    // first, remove any prefetched data from our buffer
    if (scannerScanLocation(self) < (bufferOffset + bufferLength)) {
        NSInteger prefetchedCharactersCount = (bufferOffset + bufferLength) - scannerScanLocation(self);
        
        // this may raise, if the cursor is not seekable and/or has buffered some characters in a non-simple encoding
        [streamCursor seekToOffset: -prefetchedCharactersCount fromPosition:OWCursorSeekFromCurrent];

        if (scannerScanLocation(self) > bufferOffset) {
            bufferLength = scannerScanLocation(self) - bufferOffset;
        } else {
            bufferLength = 0;
        }
    }
    
    // update the OFCharacterScanner's notion of its buffered data, as well
    scanEnd = scanLocation;
    
    if (firstNonASCIIOffset >= (inputStringPosition + (scanEnd - inputBuffer)))
        firstNonASCIIOffset = NSNotFound;
}

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    if (buffer) {
        [debugDictionary setObject:[NSString stringWithCharacters:inputBuffer length:scanEnd - inputBuffer] forKey:@"inputString"];
        [debugDictionary setObject:[NSString stringWithFormat:@"%lu", bufferLength] forKey:@"bufferLength"];
        [debugDictionary setObject:[NSString stringWithFormat:@"%lu", bufferOffset] forKey:@"bufferOffset"];
    }
    [debugDictionary setObject:streamCursor forKey:@"streamCursor"];

    return debugDictionary;
}

@end
