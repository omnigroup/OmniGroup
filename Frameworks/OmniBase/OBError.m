// Copyright 1997-2005, 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniBase/OBError.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$")

// If this is built as part of a tool (like the OSU check tool), we won't get a bundle identifier defined.
#ifndef OMNI_BUNDLE_IDENTIFIER
    #define OMNI_BUNDLE_IDENTIFIER @"com.omnigroup.framework.OmniBase"
#endif
NSString * const OBErrorDomain = OMNI_BUNDLE_IDENTIFIER;
NSString * const OBFileNameAndNumberErrorKey = @"com.omnigroup.framework.OmniBase.ErrorDomain.FileLineAndNumber";

static NSMutableDictionary *_createUserInfo(NSString *firstKey, va_list args)
{
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    
    NSString *key = firstKey;
    while (key) { // firstKey might be nil
	id value = va_arg(args, id);
        if (value)
            [userInfo setObject:value forKey:key];
	key = va_arg(args, id);
    }
    
    return userInfo;
}


static NSError *_OBWrapUnderlyingErrorv(NSError *underlyingError, NSString *domain, int code, const char *fileName, unsigned int line, NSString *firstKey, va_list args)
{
    NSMutableDictionary *userInfo = _createUserInfo(firstKey, args);
    
    // Add in the previous error, if there was one
    if (underlyingError) {
	OBASSERT(![userInfo objectForKey:NSUnderlyingErrorKey]); // Don't pass NSUnderlyingErrorKey in the varargs to this macro, silly!
	[userInfo setObject:underlyingError forKey:NSUnderlyingErrorKey];
    }
    
    // Add in file and line information if the file was supplied
    if (fileName) {
	NSString *fileString = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:fileName length:strlen(fileName)];
	[userInfo setObject:[fileString stringByAppendingFormat:@":%d", line] forKey:OBFileNameAndNumberErrorKey];
    }
    
#if INCLUDE_BACKTRACE_IN_ERRORS
    {
        const int maxFrames = 200;
        void *frames[maxFrames];
        int frameCount = backtrace(frames, maxFrames);
        if (frameCount > 0) {
            [userInfo setObject:[NSData dataWithBytes:frames length:sizeof(frames[0]) * frameCount]
                         forKey:OBBacktraceAddressesErrorKey];
        }
    }
#endif
    
    NSError *error = [NSError errorWithDomain:domain code:code userInfo:userInfo];
    [userInfo release];
    return error;
}

/*" Convenience function, invoked by the OBError macro, that allows for creating error objects with user info objects without creating a dictionary object.  The keys and values list must be terminated with a nil key. "*/
NSError *_OBWrapUnderlyingError(NSError *underlyingError, NSString *domain, int code, const char *fileName, unsigned int line, NSString *firstKey, ...)
{
    OBPRECONDITION(domain != nil && [domain length] > 0);
    
    va_list args;
    va_start(args, firstKey);
    NSError *result = _OBWrapUnderlyingErrorv(underlyingError, domain, code, fileName, line, firstKey, args);
    va_end(args);
    return result;
}


// Returns the first error that isn't one of the errors created by OBChainError. This will likely have some more useful information for reporting to the user.
NSError *OBFirstUnchainedError(NSError *error)
{
    while (error) {
        if (![[error domain] isEqualToString:OBErrorDomain] || [error code] != OBErrorChained)
            break;
        error = [[error userInfo] objectForKey:NSUnderlyingErrorKey];
    }
    return error;
}

NSError *_OBErrorWithErrnoObjectsAndKeys(int errno_value, const char *function, NSString *argument, NSString *localizedDescription, ...)
{
    NSMutableString *description = [[NSMutableString alloc] init];
    if (function)
        [description appendFormat:@"%s: ", function];
    if (argument) {
        [description appendString:argument];
        [description appendString:@": "];
    }
    [description appendFormat:@"%s", strerror(errno_value)];
    
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    [userInfo setObject:description forKey:NSLocalizedFailureReasonErrorKey];
    [description release];
    if (localizedDescription)
        [userInfo setObject:localizedDescription forKey:NSLocalizedDescriptionKey];
    
    va_list kvargs;
    va_start(kvargs, localizedDescription);
    for(;;) {
        NSObject *anObject = va_arg(kvargs, NSObject *);
        if (!anObject)
            break;
        NSString *aKey = va_arg(kvargs, NSString *);
        if (!aKey) {
            NSLog(@"*** OBErrorWithErrnoObjectsAndKeys(..., %s, %@, ...) called with an odd number of varargs!", function, localizedDescription);
            break;
        }
        [userInfo setObject:anObject forKey:aKey];
    }
    va_end(kvargs);
    
    NSError *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno_value userInfo:userInfo];
    [userInfo release];
    return error;
}

