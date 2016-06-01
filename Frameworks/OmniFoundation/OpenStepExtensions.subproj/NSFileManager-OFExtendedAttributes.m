// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSFileManager-OFExtendedAttributes.h>

#import <sys/xattr.h>

RCS_ID("$Id$");

@implementation NSFileManager (OFExtendedAttributes)

- (NSSet<NSString *> * _Nullable)listExtendedAttributesForItemAtPath:(NSString *)path error:(NSError **)outError;
{
    const char *xattrPath = [path cStringUsingEncoding:NSUTF8StringEncoding];
    
    ssize_t namebufSize = listxattr(xattrPath, NULL, 0, XATTR_NOFOLLOW);
    if (namebufSize == 0) {
        return [NSSet set];
    } else if (namebufSize < 0) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
        return nil;
    }
    
    char *namebuf = malloc(namebufSize);
    ssize_t fetchedSize = listxattr(xattrPath, namebuf, namebufSize, XATTR_NOFOLLOW);
    if (fetchedSize != namebufSize) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
        free(namebuf);
        return nil;
    }
    
    NSMutableSet *result = [NSMutableSet set];
    ssize_t offset = 0;
    while (offset < namebufSize) {
        void *offsetBuf = namebuf + offset;
        size_t nameLen = strnlen(offsetBuf, namebufSize - offset);
        NSString *xattr = [[[NSString alloc] initWithBytes:offsetBuf length:nameLen encoding:NSUTF8StringEncoding] autorelease];
        [result addObject:xattr];
        offset += (nameLen + 1); // account for the NUL byte that terminated the string
    }
    
    free(namebuf);
    return result;
}

- (NSData *)extendedAttribute:(NSString *)xattr forItemAtPath:(NSString *)path error:(NSError **)outError;
{
    const char *xattrPath = [path cStringUsingEncoding:NSUTF8StringEncoding];
    const char *xattrName = [xattr cStringUsingEncoding:NSUTF8StringEncoding];
    
    ssize_t xattrSize = getxattr(xattrPath, xattrName, NULL, 0, 0, XATTR_NOFOLLOW);
    if (xattrSize == -1) {
        switch (errno) {
            case ENOATTR:
                // Don't populate an error if the attribute just doesn't exist
                break;
                
            default:
                if (outError) {
                    *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
                }
        }
        return nil;
    }
    
    void *value = malloc(xattrSize);
    ssize_t fetchedSize = getxattr(xattrPath, xattrName, value, xattrSize, 0, XATTR_NOFOLLOW);
    if (xattrSize != fetchedSize) {
        if (fetchedSize == -1 && outError) {
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        }
        
        free(value);
        return nil;
    }
    
    NSData *result = [NSData dataWithBytes:value length:fetchedSize];
    free(value);
    return result;
}

- (BOOL)setExtendedAttribute:(NSString *)xattr data:(NSData * _Nullable)data forItemAtPath:(NSString *)path error:(NSError **)outError;
{
    // Allow "set nil" as another way of expressing "remove"
    if (data == nil) {
        return [self removeExtendedAttribute:xattr forItemAtPath:path error:outError];
    }
    
    const char *xattrPath = [path cStringUsingEncoding:NSUTF8StringEncoding];
    const char *xattrName = [xattr cStringUsingEncoding:NSUTF8StringEncoding];
    
    size_t dataSize = [data length];
    void *value = malloc(dataSize);
    [data getBytes:value range:NSMakeRange(0, dataSize)];
    
    int success = setxattr(xattrPath, xattrName, value, dataSize, 0, XATTR_NOFOLLOW);
    free(value);
    switch (success) {
        case 0:
            return YES;
            
        default:
            if (outError) {
                *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            }
            return NO;
    }
}

- (BOOL)removeExtendedAttribute:(NSString *)xattr forItemAtPath:(NSString *)path error:(NSError **)outError;
{
    const char *xattrPath = [path cStringUsingEncoding:NSUTF8StringEncoding];
    const char *xattrName = [xattr cStringUsingEncoding:NSUTF8StringEncoding];
    
    int success = removexattr(xattrPath, xattrName, XATTR_NOFOLLOW);
    switch (success) {
        case 0:
            return YES;
            
        case ENOATTR:
            return YES; // if the xattr didn't exist, we can claim success in removing it
            
        default:
            if (outError) {
                *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            }
            return NO;
    }
}

@end
