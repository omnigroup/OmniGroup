// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniNetworking/ONSocket.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniBase/OBObject.h>

@class NSData;
@class NSMutableData;

#import <Foundation/NSString.h> // for NSStringEncoding

@interface ONSocket : OBObject
{
    NSStringEncoding stringEncoding;
    unsigned int readBufferSize;
}

// These are the primitive methods which must be implemented by subclasses
- (unsigned int)readBytes:(unsigned int)byteCount intoBuffer:(void *)aBuffer;
- (unsigned int)writeBytes:(unsigned int)byteCount fromBuffer:(const void *)aBuffer;
- (void)abortSocket;

- (BOOL)isReadable;
- (BOOL)isWritable;

// This is implemented in terms of -writeBytes:fromBuffer:, but overridden in subclasses which support 'gather' writing directly.
- (unsigned int)writeBuffers:(const struct iovec *)buffers count:(unsigned int)num_iov;

@end

@interface ONSocket (General)

// These methods operate in terms of the primitive methods, and therefore need not be implemented by subclasses.

+ (void)setDefaultStringEncoding:(NSStringEncoding)aStringEncoding;
+ (void)setDefaultReadBufferSize:(int)aSize;

- (void)writeData:(NSData *)data;
- (void)writeString:(NSString *)aString;
- (void)writeFormat:(NSString *)aFormat, ...;
- (void)readData:(NSMutableData *)data;
- (NSData *)readData;
- (NSString *)readString;

- (NSStringEncoding)stringEncoding;
- (void)setStringEncoding:(NSStringEncoding)aStringEncoding;
- (void)setReadBufferSize:(int)aSize;

@end
