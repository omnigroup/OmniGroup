// Copyright 2000-2005, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OWF/OWCursor.h>

@class NSData;
@class OWDataStream, OWDataStreamCursor;

#import <OmniFoundation/OFStringDecoder.h>

@interface OWDataStreamCharacterCursor : OWCursor
{
    OWDataStreamCursor *byteSource;

    enum {
        se_simple_OF,           // a 1-byte-1-char encoding supported by OF
        se_simple_Foundation,   // 1-byte-1-char, but we use NSString methods
        se_complex_OF,          // multibyte seq.s or shift characters
        se_complex_Foundation   // multibyte or shifts, and not in OF
    } stringEncodingType;
    
    /* Used by Foundation-based conversion methods */
    CFStringEncoding stringEncoding;

    /* OmniFoundation conversion state */
    struct OFStringDecoderState conversionState;
    
    /* For peeking and so forth */
    NSString *stringBuffer;
    NSRange stringBufferValidRange;
}

- initForDataCursor:(OWDataStreamCursor *)source encoding:(CFStringEncoding)anEncoding;

/* Examining the underlying byte stream */
/* Note that the character cursor will read ahead in the byte stream; you cannot assume that the DataStreamCursor's current position reflects the CharacterCursor's current position */
- (OWDataStreamCursor *)dataStreamCursor;
// - (unsigned int)byteOffsetForCurrentCharacterOffset;
- (void)discardReadahead;   /* rewinds the byte stream, etc. */
// - (void)ungetCharacters:(NSString *)buffer;   /* implementable if someone wants it */
- (void)setCFStringEncoding:(CFStringEncoding)aStringEncoding;
- (CFStringEncoding)stringEncoding;
// - (void)setEncoding:(NSStringEncoding)newEncoding; /* "deprecated", heh */

- (NSUInteger)seekToOffset:(NSInteger)offset fromPosition:(OWCursorSeekPosition)position;  /* calls -discardReadahead and then seeks the underlying stream; may raise if using a multibyte encoding; may not behave correctly if seeking across changes in character encodings */

/* Reading characters and strings. Both of these can return 0 characters before EOF due to multibyte encoding wackiness. */
- (NSUInteger)readCharactersIntoBuffer:(unichar *)buffer maximum:(NSUInteger)bufferSize peek:(BOOL)updateCursorPosition; /* fast; returns 0 at eof; use -isAtEOF to distinguish */
- (NSString *)readString;  /* reads what's available; returns nil at eof */
- (NSString *)readAllAsString;  /* reads until EOF, blocking if necessary */
- (BOOL)isAtEOF;

/* Reading lines, terminated by CR, LF, or CRLF. Returns nil at EOF. */
- (NSString *)readLineAndAdvance:(BOOL)shouldAdvance;
- (NSString *)readLine;
- (NSString *)peekLine;
- (void)skipLine;

/* Reading tokens. Raises an exception at EOF, because that's what the code I'm replacing did. */
- (NSString *)readTokenAndAdvance:(BOOL)shouldAdvance;
- (NSString *)readToken;
- (NSString *)peekToken;

/* The readTextInt and peekTextInt methods aren't carried over. Use [[... readToken] intValue] instead. */

/* For scanning ahead. I haven't implemented this; is it used anywhere? */
// - (unsigned)scanUntilStringRead:(NSString *)stringMatch;
// better name: - (unsigned int)scanPastString:(NSString *)stringMatch;

@end
