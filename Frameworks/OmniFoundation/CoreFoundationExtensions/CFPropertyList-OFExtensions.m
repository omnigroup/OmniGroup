// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniBase/rcsid.h>

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/NSPropertyList.h>
#import <OmniFoundation/OFCFCallbacks.h>

RCS_ID("$Id$")

CFPropertyListRef OFCreatePropertyListFromFile(CFStringRef filePath, CFPropertyListMutabilityOptions options, CFErrorRef *outError)
{
    CFReadStreamRef stream;
    
    CFURLRef fileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, filePath, kCFURLPOSIXPathStyle, FALSE);
    if (!fileURL || !(stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, fileURL))) {
        if (outError) {
            const void *keys[1], *values[1];
            keys[0] = NSFilePathErrorKey;
            values[0] = filePath;
            *outError = CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, (CFStringRef)NSCocoaErrorDomain, NSFileReadUnknownError, keys, values, 1);
        }
        if (fileURL) 
            CFRelease(fileURL);

        return NULL;
    }
    CFRelease(fileURL);
    CFReadStreamOpen(stream);
    {
        CFErrorRef openError = CFReadStreamCopyError(stream);
        if (openError) {
            if (outError)
                *outError = openError;
            else
                CFRelease(openError);
            CFRelease(stream);
            return NULL;
        }
    }
    
    CFPropertyListRef result = CFPropertyListCreateWithStream(kCFAllocatorDefault, stream, 0/*read to end of stream*/, options, NULL, outError);
    CFReadStreamClose(stream);
    CFRelease(stream);
    
    return result;
}

id OFReadNSPropertyListFromURL(NSURL *fileURL, NSError **outError)
{
    NSData *data = [[NSData alloc] initWithContentsOfURL:fileURL options:NSDataReadingUncached error:outError];
    if (!data)
        return nil;
    
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:outError];
    [data release];
    return plist;
}

BOOL OFWriteNSPropertyListToURL(id plist, NSURL *fileURL, NSError **outError)
{
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:outError];
    if (!data)
        return NO;
    
    return [data writeToURL:fileURL options:0 error:outError];
}

#ifdef DEBUG


@interface NSObject (Private)
- (BOOL)isNSCFConstantString__;
@end

static BOOL isTaggedPointer(id object) {
    // This isn't API, but right now at least the low bit is set on x86_64.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-objc-pointer-introspection"
    return ((uintptr_t)object) & 0x1;
#pragma clang diagnostic pop
}

static BOOL isConstant(id object) {
    return isTaggedPointer(object) || [object isNSCFConstantString__];
}

@interface NSObject (OFDuplicatePropertyListentries)
- (NSUInteger)_reportDuplicatePropertyListEntries:(NSString *)path uniquingTable:(NSMutableSet *)table;
- (void)_addPointersToTable:(CFMutableSetRef)table;
@end

@implementation NSObject (OFDuplicatePropertyListentries)

- (NSUInteger)_reportDuplicatePropertyListEntries:(NSString *)path uniquingTable:(NSMutableSet *)table;
{
    id existing = [table member:self];
    if (!existing) {
        // New unique object
        [table addObject:self];
        return 0;
    }

    if (isConstant(existing)) {
        if (isConstant(self)) {
            // Don't complain about constant-string vs tagged-pointer string, tagged pointer numbers vs shared boolean numbers, and the like.
            return 0;
        } else {
            // Put the non-constant object in the table (and complain once here).
            [table addObject:self];
        }
    } else if (isConstant(self)) {
        // Don't complain about constant vs a non-constant in the table.
        return 0;
    } else if (existing == self) {
        // Repeated reference to the same object.
        return 0;
    }

    // Equal object with non-equal pointer.
    NSLog(@"Duplicate instance %@ at %@, previous is %@", OBShortObjectDescription(self), path, OBShortObjectDescription(existing));
    return 1;
}

- (void)_addPointersToTable:(CFMutableSetRef)table;
{
    CFSetAddValue(table, (const void **)self);
}

@end

@interface NSArray (OFDuplicatePropertyListentries)
- (NSUInteger)_reportDuplicatePropertyListEntries:(NSString *)path uniquingTable:(NSMutableSet *)table;
@end

@implementation NSArray (OFDuplicatePropertyListentries)
- (NSUInteger)_reportDuplicatePropertyListEntries:(NSString *)path uniquingTable:(NSMutableSet *)table;
{
    if ([super _reportDuplicatePropertyListEntries:path uniquingTable:table] > 0) {
        return 1; // The whole collection is a duplicate; don't report members.
    }

    __block NSUInteger count = 0;
    [self enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *subpath = [[NSString alloc] initWithFormat:@"%@.%lu", path, idx];
        count += [obj _reportDuplicatePropertyListEntries:subpath uniquingTable:table];
        [subpath release];
    }];
    return count;
}

- (void)_addPointersToTable:(CFMutableSetRef)table;
{
    [super _addPointersToTable:table];

    for (id object in self) {
        [object _addPointersToTable:table];
    }
}

@end

@interface NSDictionary (OFDuplicatePropertyListentries)
- (NSUInteger)_reportDuplicatePropertyListEntries:(NSString *)path uniquingTable:(NSMutableSet *)table;
@end

@implementation NSDictionary (OFDuplicatePropertyListentries)
- (NSUInteger)_reportDuplicatePropertyListEntries:(NSString *)path uniquingTable:(NSMutableSet *)table;
{
    if ([super _reportDuplicatePropertyListEntries:path uniquingTable:table] > 0) {
        return 1; // The whole collection is a duplicate; don't report members.
    }

    __block NSUInteger count = 0;
    [self enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull object, BOOL * _Nonnull stop) {
        NSString *subpath = [[NSString alloc] initWithFormat:@"%@.key(%@)", path, key];
        count += [key _reportDuplicatePropertyListEntries:subpath uniquingTable:table];
        [subpath release];

        subpath = [[NSString alloc] initWithFormat:@"%@.%@", path, key];
        count += [object _reportDuplicatePropertyListEntries:subpath uniquingTable:table];
        [subpath release];
    }];
    return count;
}

- (void)_addPointersToTable:(CFMutableSetRef)table;
{
    [super _addPointersToTable:table];

    [self enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull object, BOOL * _Nonnull stop) {
        [key _addPointersToTable:table];
        [object _addPointersToTable:table];
    }];
}
@end

void OFReportDuplicatePropertyListEntries(id plist)
{
    NSMutableSet *table = [NSMutableSet set];
    NSUInteger count = [plist _reportDuplicatePropertyListEntries:@"" uniquingTable:table];
    NSLog(@"%lu duplicate objects found", count);
}

void OFReportPointerCountInPropertyList(id plist)
{
    CFMutableSetRef table = CFSetCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerSetCallbacks);
    [plist _addPointersToTable:table];
    NSLog(@"%lu distinct pointers found", CFSetGetCount(table));
    CFRelease(table);
}

#endif
