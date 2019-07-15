// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBObject.h>
#import <OmniBase/system.h>

@class NSData;
@class NSMutableData;

#import <Foundation/NSString.h> // for NSStringEncoding

@interface ONSocket : OBObject

// These are the primitive methods which must be implemented by subclasses
- (size_t)readBytes:(size_t)byteCount intoBuffer:(void *)aBuffer;
- (size_t)writeBytes:(size_t)byteCount fromBuffer:(const void *)aBuffer;
- (void)abortSocket;

- (BOOL)isReadable;
- (BOOL)isWritable;

// This is implemented in terms of -writeBytes:fromBuffer:, but overridden in subclasses which support 'gather' writing directly.
- (size_t)writeBuffers:(const struct iovec *)buffers count:(unsigned int)num_iov;

@end

@interface ONSocket (General)

// These methods operate in terms of the primitive methods, and therefore need not be implemented by subclasses.

+ (void)setDefaultStringEncoding:(NSStringEncoding)aStringEncoding;
+ (void)setDefaultReadBufferSize:(int)aSize;

- (void)writeData:(NSData *)data;
- (void)writeString:(NSString *)aString;
- (void)writeFormat:(NSString *)aFormat, ... NS_FORMAT_FUNCTION(1,2);
- (void)readData:(NSMutableData *)data;
- (NSData *)readData;
- (NSString *)readString;

- (NSStringEncoding)stringEncoding;
- (void)setStringEncoding:(NSStringEncoding)aStringEncoding;
- (void)setReadBufferSize:(int)aSize;

@end
