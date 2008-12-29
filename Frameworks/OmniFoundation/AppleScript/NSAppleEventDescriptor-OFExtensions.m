// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSAppleEventDescriptor-OFExtensions.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@implementation NSAppleEventDescriptor (OFExtensions)

/*" This actually takes any kind of URL, but the AEDesc type is 'furl' which suggests it should only be used for urls that point to files (presumably on the local filesystem?) "*/
+ (NSAppleEventDescriptor *)descriptorWithFileURL:(NSURL *)furl;
{
    if (!furl)
        return nil;
    
    /* See http://developer.apple.com/technotes/tn/tn2022.html */
    /* As of 10.5, at least, Finder seems to be accepting these */
    
    CFDataRef urlBytes = CFURLCreateData(kCFAllocatorDefault, (CFURLRef)furl, kCFStringEncodingUTF8, true);
    if (urlBytes == NULL) {
        [NSException raise:NSInternalInconsistencyException format:@"Unable to extract bytes of URL (%@)", furl];
    }
    
    NSAppleEventDescriptor *result = [self descriptorWithDescriptorType:typeFileURL data:(NSData *)urlBytes];
    
    CFRelease(urlBytes);
    
    return result;
}

@end

@implementation NSDictionary (OFExtensions_NSAppleEventDescriptor)

+ (NSDictionary *)dictionaryWithUserRecord:(NSAppleEventDescriptor *)descriptor;
{
    if (!(descriptor = [descriptor descriptorForKeyword:'usrf']))
        return nil;
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    int itemIndex, itemCount = [descriptor numberOfItems];
    
    for (itemIndex = 1; itemIndex <= itemCount; itemIndex += 2) {
        NSString *key = [[descriptor descriptorAtIndex:itemIndex] stringValue];
	id valueObject = [descriptor descriptorAtIndex:itemIndex+1];
	
	if ([valueObject typeCodeValue] == FOUR_CHAR_CODE('msng')) {
	    [result setObject:[NSNull null] forKey:key];
	    continue;
	}
	
        NSString *value = [valueObject stringValue];
        [result setObject:value forKey:key];
    }
    return result;
}

- (NSAppleEventDescriptor *)userRecordValue;
{
    NSAppleEventDescriptor *listDescriptor = [NSAppleEventDescriptor listDescriptor];
    NSEnumerator *enumerator = [self keyEnumerator];
    NSString *key;
    int listCount = 0;
    
    while ((key = [enumerator nextObject])) {
        [listDescriptor insertDescriptor:[NSAppleEventDescriptor descriptorWithString:key] atIndex:++listCount];
        id value = [self objectForKey:key];
	if (value == [NSNull null])
	    [listDescriptor insertDescriptor:[NSAppleEventDescriptor descriptorWithTypeCode:FOUR_CHAR_CODE('msng')] atIndex:++listCount];
	else 
	    [listDescriptor insertDescriptor:[NSAppleEventDescriptor descriptorWithString:[value description]] atIndex:++listCount];
    }
    
    NSAppleEventDescriptor *result = [NSAppleEventDescriptor recordDescriptor];
    [result setDescriptor:listDescriptor forKeyword:'usrf'];
    return result;
}

@end
