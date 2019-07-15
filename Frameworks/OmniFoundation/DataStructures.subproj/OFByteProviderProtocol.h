// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

/*
 OFByteProvider / OFByteAcceptor describes an abstract interface for things that look a bit like buffers and can accept chunks of data at arbitrary offsets. If NSStream/CFStream is analogous to a pipe or socket, then OFByteProvider/Acceptor is equivalent to a file or a block device.
 
 The method names are chosen so that NSData and NSMutableData conform to the protocol without any category additions. This does have one drawback, which is that the user of OFByteAcceptor needs to explicitly manage increasing the length of the acceptor as needed (instead of having the file-like behavior of automatically extending to encompass a write).
 
 The -getBuffer:range: optional method is modeled on NSInputStream's method of the same name, except that the buffer is explicitly released by the caller instead of implicitly some time after the next call into the API.
 
 I'm not sure whether this or the implicit behavior is better--- allowing the caller to extend the lifetime of the buffer like this means that the provider must have the capability to write future data into a different buffer (and the whole point of that method is to avoid all the redundant buffer->buffer copying logic). As of yet nobody implements or uses that method so we can change its behavior easily if we need to. On the other hand, the implicit behavior means that the acceptor is more stateful.
*/

#import <Foundation/NSRange.h>

typedef void (^OFByteProviderBufferRelease)(void);

@protocol OFByteProvider

/* Methods implemented by NSData */
@property(nonatomic,readonly) NSUInteger length;
- (void)getBytes:(void *)buffer range:(NSRange)range;

/* Methods we may implement on specialized providers */
@optional
- (OFByteProviderBufferRelease)getBuffer:(const void **)buffer range:(NSRange *)range;
// returns in O(1) a pointer to the buffer in 'buffer' and by reference in 'len' how many bytes are available. This buffer is only valid until the next stream operation. Subclassers may return NO for this if it is not appropriate for the stream type. This may return NO if the buffer is not available.

- (NSError *)error;

@end


@protocol OFByteAcceptor

/* Methods implemented by NSMutableData */
@property(nonatomic,readwrite) NSUInteger length;
- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes;

@optional

- (void)flushByteAcceptor;
- (NSError *)error;

@end

#import <Foundation/NSData.h>

@interface NSData () <OFByteProvider>
@end

@interface NSMutableData () <OFByteAcceptor>
@end


