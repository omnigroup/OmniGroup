// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// This tool tests the OFMutableKnownKeyDictionary class.

#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

static NSString *key1 = @"key1";
static NSString *key2 = @"key2";
static NSString *key3 = @"key3";
static NSString *key4 = @"key4";

static NSString *value1 = @"value1";
static NSString *value2 = @"value2";
static NSString *value3 = @"value3";
static NSString *value4 = @"value4";

int main(int argc, const char *argv[])
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    NSArray                      *keys1, *keys2, *keys3;
    OFKnownKeyDictionaryTemplate *template1, *template2, *template3;
    OFMutableKnownKeyDictionary  *dict1, *dict2, *dict3;
    NSEnumerator                 *e;
    NSObject                     *value;
    
    keys1 = [NSArray arrayWithObjects: key1, key2, key3, key4, nil];
    keys2 = [NSArray arrayWithObjects: key1, key2, key3, nil];
    keys3 = [NSArray arrayWithObjects: key1, nil];

    template1 = [OFKnownKeyDictionaryTemplate templateWithKeys: keys1];
    template2 = [OFKnownKeyDictionaryTemplate templateWithKeys: keys2];
    template3 = [OFKnownKeyDictionaryTemplate templateWithKeys: keys3];

    NSLog(@"templates = %@, %@, %@", template1, template2, template3);

    dict1 = [OFMutableKnownKeyDictionary newWithTemplate: template1];
    dict2 = [OFMutableKnownKeyDictionary newWithTemplate: template1];
    dict3 = [OFMutableKnownKeyDictionary newWithTemplate: template1];
    NSLog(@"empty = %@, %@, %@", dict1, dict2, dict3);

    [dict1 setObject: value1 forKey: key1];
    NSLog(@"dict1(key1=value1) = %@", dict1);
    [dict1 setObject: value2 forKey: key2];
    NSLog(@"dict1(key1=value1,key2=value2) = %@", dict1);
    [dict1 setObject: value3 forKey: key3];
    [dict1 setObject: value4 forKey: key4];
    NSLog(@"dict1(all) = %@", dict1);

    NSLog(@"dict1, non-ptr-equal (key1) = %@", [dict1 objectForKey: [NSString stringWithCString: "key1"]]);
    NSLog(@"dict1, non-ptr-equal (key2) = %@", [dict1 objectForKey: [NSString stringWithCString: "key2"]]);
    NSLog(@"dict1, non-ptr-equal (key3) = %@", [dict1 objectForKey: [NSString stringWithCString: "key3"]]);
    NSLog(@"dict1, non-ptr-equal (key4) = %@", [dict1 objectForKey: [NSString stringWithCString: "key4"]]);

    NS_DURING {
        NSLog(@"setting non-known key");
        [dict1 setObject: @"bogus" forKey: @"bogus"];
    } NS_HANDLER {
        NSLog(@"exception = %@", localException);
    } NS_ENDHANDLER;

    NSLog(@"keys   = %@", [dict1 allKeys]);
    NSLog(@"values = %@", [dict1 allValues]);

    NSLog(@"enumerating keys (key1, key2, key3, key4):");
    e = [dict1 keyEnumerator];
    while ((value = [e nextObject]))
        NSLog(@"\t%@", value);
    NSLog(@"enumerating objects (value1, value2, value3, value4):");
    e = [dict1 objectEnumerator];
    while ((value = [e nextObject]))
        NSLog(@"\t%@", value);

    [dict1 removeObjectForKey: key1];
    NSLog(@"enumerating keys (key2, key3, key4):");
    e = [dict1 keyEnumerator];
    while ((value = [e nextObject]))
        NSLog(@"\t%@", value);
    NSLog(@"enumerating objects (value2, value3, value4):");
    e = [dict1 objectEnumerator];
    while ((value = [e nextObject]))
        NSLog(@"\t%@", value);

    [dict1 removeObjectForKey: key3];
    [dict1 removeObjectForKey: key4];
    NSLog(@"enumerating keys (key2):");
    e = [dict1 keyEnumerator];
    while ((value = [e nextObject]))
        NSLog(@"\t%@", value);
    NSLog(@"enumerating objects (value2):");
    e = [dict1 objectEnumerator];
    while ((value = [e nextObject]))
        NSLog(@"\t%@", value);

    [dict1 removeObjectForKey: key2];
    [dict1 removeObjectForKey: key2];
    NSLog(@"enumerating keys ():");
    e = [dict1 keyEnumerator];
    while ((value = [e nextObject]))
        NSLog(@"\t%@", value);
    NSLog(@"enumerating objects ():");
    e = [dict1 objectEnumerator];
    while ((value = [e nextObject]))
        NSLog(@"\t%@", value);

    [pool release];
    return 0;
}
