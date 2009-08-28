// Copyright 2003-2005, 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLInternedStringTable.h>

#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/OFXMLQName.h>
#import <libxml/xmlstring.h>


RCS_ID("$Id$");

static inline CFHashCode _stringHash(const char *str)
{
    // We don't expect to get long strings, so use the whole thing
    CFHashCode hash = 0;
    char c;
    while ((c = *str)) {
        hash = hash * 257 + c;
        str++;
    }
    
    return hash;
}

#define TABLE ((CFMutableDictionaryRef)table)

static void InternedStringKeyRelease(CFAllocatorRef allocator, const void *value)
{
    free((xmlChar *)value);
}

static Boolean InternedStringKeyEqual(const void *value1, const void *value2)
{
    return strcmp((const char *)value1, (const char *)value2) == 0;
}

static CFHashCode InternedStringKeyHash(const void *value)
{
    const char *str = (const char *)value;
    return _stringHash(str);
}

OFXMLInternedStringTable OFXMLInternedStringTableCreate(NSSet *startingStrings)
{
    // Map NUL terminated UTF-8 byte strings to NSString instances that wrap them to avoid creating lots of copies of the same string.
    CFDictionaryKeyCallBacks keyCallbacks;
    memset(&keyCallbacks, 0, sizeof(keyCallbacks));
    keyCallbacks.release = InternedStringKeyRelease;
    keyCallbacks.equal = InternedStringKeyEqual;
    keyCallbacks.hash = InternedStringKeyHash;

    // Lie about the type.  There is no such struct.
    OFXMLInternedStringTable table = (struct _OFXMLInteredStringTable *)CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallbacks, &OFNSObjectDictionaryValueCallbacks);
    
    // We should point at *exactly* these string instances so that users can use == comparison.
    for (NSString *string in startingStrings) {
        const char *key = strdup([string UTF8String]);
        OBASSERT(CFDictionaryGetValue(TABLE, key) == NULL);
        CFDictionarySetValue(TABLE, key, string);
    }
    
    return table;
}

void OFXMLInternedStringTableFree(OFXMLInternedStringTable table)
{
    OBPRECONDITION(table);
    if (TABLE)
        CFRelease(TABLE);
}

NSString *OFXMLInternedStringTableGetInternedString(OFXMLInternedStringTable table, const char *str)
{
    OBPRECONDITION(str);
    
    NSString *interned = (NSString *)CFDictionaryGetValue(TABLE, str);
    if (interned)
        return interned;
    
    const char *key = strdup(str); // caller owns the input.
    interned = [[NSString alloc] initWithUTF8String:key]; // the extra ref here is the 'create' returned to the caller
    CFDictionarySetValue(TABLE, key, interned); // dictionary retains the intered string for the life of 'state' too.
    
    //NSLog(@"XML: Interned string '%@'", interned);
    
    return interned;
}

#pragma mark -

static const char * const EmptyString = "";

typedef struct {
    const char *namespace;
    const char *name;
} QNameKey;

static void QNameRelease(CFAllocatorRef allocator, const void *value)
{
    QNameKey *qname = (QNameKey *)value;
    
    if (qname->namespace != EmptyString)
        free((char *)qname->namespace);
    if (qname->name != EmptyString)
        free((char *)qname->name);
    
    free(qname);
}

static Boolean QNameKeyEqual(const void *value1, const void *value2)
{
    const QNameKey *key1 = value1;
    const QNameKey *key2 = value2;
    
    // We upgrade NULL to EmptyString to make this easier.
    return (strcmp(key1->name, key2->name) == 0) && (strcmp(key1->namespace, key2->namespace) == 0);
}

static CFHashCode QNameKeyHash(const void *value)
{
    const QNameKey *key = value;
    
    // We upgrade NULL to EmptyString to make this easier.
    return _stringHash(key->name) ^ _stringHash(key->namespace);
}

static const char *_personalizeString(const char *str)
{
    if (!str || !*str)
        return EmptyString;
    return strdup(str);
}

OFXMLInternedNameTable OFXMLInternedNameTableCreate(OFXMLInternedNameTable startingQNameTable)
{
    // Map a tuple of NUL terminated UTF-8 byte strings to OFXMLQName instances that wrap them to avoid creating lots of copies of the same string.
    CFDictionaryKeyCallBacks keyCallbacks;
    memset(&keyCallbacks, 0, sizeof(keyCallbacks));
    keyCallbacks.release = QNameRelease;
    keyCallbacks.equal = QNameKeyEqual;
    keyCallbacks.hash = QNameKeyHash;
    
    // Lie about the type.  There is no such struct.
    OFXMLInternedNameTable table = (struct _OFXMLInternedNameTable *)CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallbacks, &OFNSObjectDictionaryValueCallbacks);
    
    // We should point at *exactly* these name instances so that users can use == comparison.
    for (OFXMLQName *qname in [(NSDictionary *)startingQNameTable allValues]) {
        QNameKey *key = malloc(sizeof(*key));
        
        // TODO: We are potentially making lots of copies of the same namespace string, one per attribute/element in that namespace.
        key->namespace = _personalizeString([qname.namespace UTF8String]);
        key->name = _personalizeString([qname.name UTF8String]);
        
        OBASSERT(CFDictionaryGetValue(TABLE, key) == NULL);
        CFDictionarySetValue(TABLE, key, qname);
    }
    
    return table;
}

void OFXMLInternedNameTableFree(OFXMLInternedNameTable table)
{
    OBPRECONDITION(table);
    if (TABLE)
        CFRelease(TABLE);
}

OFXMLQName *OFXMLInternedNameTableGetInternedName(OFXMLInternedNameTable table, const char *namespace, const char *name)
{
    OBPRECONDITION(!namespace || *namespace); // NULL namespace is allowed, but not the empty string
    OBPRECONDITION(!name || *name); // There can be no name when reading the default namespace.  We expect NULL in this case.
    
    // Upconvert to a constant empty string if we get NULL, to make the hash/compare functions easier.
    if (!namespace)
        namespace = EmptyString;
    if (!name)
        name = EmptyString;
    
    QNameKey proto = {.namespace = namespace, .name = name};
    
    OFXMLQName *interned = (OFXMLQName *)CFDictionaryGetValue(TABLE, &proto);
    if (interned)
        return interned;
    
    // TODO: This could lead to a number of repeated copies of namespace names. Enough to care?
    QNameKey *key = malloc(sizeof(*key));
    key->namespace = _personalizeString(namespace);
    key->name = _personalizeString(name);

    NSString *namespaceString = (namespace != EmptyString) ? [[NSString alloc] initWithCString:namespace encoding:NSUTF8StringEncoding] : @"";
    NSString *nameString = (name != EmptyString) ? [[NSString alloc] initWithCString:name encoding:NSUTF8StringEncoding] : @"";
    interned = [[OFXMLQName alloc] initWithNamespace:namespaceString name:nameString];
    [namespaceString release];
    [nameString release];
    
    CFDictionarySetValue(TABLE, key, interned);
    
    //NSLog(@"XML: Interned qname '%@'", [interned shortDescription]);
    
    return interned;
}
