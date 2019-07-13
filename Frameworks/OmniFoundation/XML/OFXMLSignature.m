// Copyright 2009-2016,2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLSignature.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSData-OFEncoding.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFCDSAUtilities.h>
#import <OmniFoundation/OFSecurityUtilities.h>
#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
#import <Security/Security.h>
#import "OFSecSignTransform.h"
#endif

#include <libxml/tree.h>

#include <libxml/c14n.h>
#include <libxml/xmlIO.h>
#include <libxml/xmlerror.h>
#include <libxml/xmlmemory.h>
#include <libxml/xmlversion.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#include <libxml/xpointer.h>

RCS_ID("$Id$");

/*
 You may wonder how I came to be living in Canada, after being royalty in Spain. You may also wonder why OF contains its own partial implementation of XML DSIG instead of using an existing implementation.
 
 My first cut used the xmlsec library that's part of GNOME, like libxml2. Unfortunately it's painfully overengineered and underdocumented; I ended up writing more code simply to interface with it than I did to rewrite from scratch, and I was far less confident that any part of that code was correct, or would remain correct when used with future versions of xmlsec.
 
 My second cut used the NSXML classes, for ObjC-y convenience and goodness. I ran into a number of bugs in that library which I couldn't find workarounds for. The RADARs are still open as of Snow Leopard, so I'm dropping that route.
 
 This is my third try, and so far it seems to be working.
 
 Some XML-DSIG features that this does not support:
 
 - XPath and XSLT transforms, and XPointer other than via URI fragment references.
 - The here() funtion in XPointer, since I don't think it's well-defined in the presence of canonicalization.
 - Manifest verification (or any special processing of Manifest nodes at all).
 - Doesn't distinguish between XML Canonicalization 1.0 and 1.1.
 - The <HMACOutputLength> parameter isn't supported, since it isn't directly supported by CSSM.
 - Other random things; see the TODOs and stuff.

*/

#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7 && MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7
// If we allow 10.7 API but also support 10.6, then we need to weakly import these Security.framework symbols or we won't be able to launch on 10.6.
extern const CFStringRef kSecDigestLengthAttribute __attribute__((weak_import));
extern const CFStringRef kSecDigestTypeAttribute __attribute__((weak_import));
extern const CFStringRef kSecDigestSHA1 __attribute__((weak_import));
extern const CFStringRef kSecDigestSHA2 __attribute__((weak_import));
#endif

/* Canonicalization algorithm identifiers */
#define XMLCanonicalization10_OmitComments    ((const xmlChar *)"http://www.w3.org/TR/2001/REC-xml-c14n-20010315")
#define XMLCanonicalization10_KeepComments    ((const xmlChar *)"http://www.w3.org/TR/2001/REC-xml-c14n-20010315#WithComments")
#define XMLCanonicalization11_OmitComments    ((const xmlChar *)"http://www.w3.org/2006/12/xml-c14n11")
#define XMLCanonicalization11_KeepComments    ((const xmlChar *)"http://www.w3.org/2006/12/xml-c14n11#WithComments")
#define XMLCanonicalizationExc10_OmitComments ((const xmlChar *)"http://www.w3.org/2001/10/xml-exc-c14n#")
#define XMLCanonicalizationExc10_KeepComments ((const xmlChar *)"http://www.w3.org/2001/10/xml-exc-c14n#WithComments")

/* Values for the <Reference Type=...> attribute */
#define XMLReferentTypeObject    ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#Object")
#define XMLReferentTypeManifest  ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#Manifest")
#define XMLReferentTypeSigProps  ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#SignatureProperties")

/* For evaluating a chain of <Transform> nodes */
/* One of these structures exists for each transform, including the final digest-or-verify "transform". 
 "ctxt" is a context pointer passed to openStream, acceptNodes, and cleanup.
 "next" points to the downstream transformation, if any.
 Either "openStream" or "acceptNodes" will be called, once, depending on whether the upstream transform produces a byte-stream or a node-set.
 "cleanup" will be called after the transform is complete or if an error occurs.
 
 Note that "acceptNodes" takes a predicate callback, not an explicit nodeset. It turns out that the transform usually ends up traversing the entire document tree and testing nodes for membership in the passed-in node set. Having an intermediate, concrete copy of the node set doesn't actually simplify the code at all.
*/
struct OFXMLSignatureVerifyContinuation {
    void *ctxt;
    struct OFXMLSignatureVerifyContinuation *next;
    xmlOutputBuffer *(*openStream)(struct OFXMLSignatureVerifyContinuation *ctxt, NSError **outError);
    BOOL (*acceptNodes)(struct OFXMLSignatureVerifyContinuation *continuation, xmlDocPtr doc, xmlC14NIsVisibleCallback is_visible_callback, void *is_visible_arg, NSError **outError);
    void (*cleanup)(void *ctxt);
};

/* Error-signaling functions */

static BOOL signatureStructuralFailure(NSError **err, NSString *fmt, ...)  __attribute__((format(__NSString__, 2, 3)));
static BOOL signatureProcessingFailure(NSError **err, enum OFXMLSignatureOperation op, NSInteger code, NSString *function, NSString *fmt, ...)
__attribute__((format(__NSString__, 5, 6)));


static BOOL signatureStructuralFailure(NSError **err, NSString *fmt, ...)
{
    if (!err)
        return NO;
    
    va_list varg;
    va_start(varg, fmt);
    NSString *descr = [[NSString alloc] initWithFormat:fmt arguments:varg];
    va_end(varg);
    
    NSString *keys[3];
    id values[3];
    NSUInteger keyCount;
    
    keys[0] = NSLocalizedDescriptionKey;
    values[0] = @"Invalid document structure while validating XML signature";
    
    keys[1] = NSLocalizedFailureReasonErrorKey;
    values[1] = descr;
    
    if (*err) {
        keys[2] = NSUnderlyingErrorKey;
        values[2] = *err;
        keyCount = 3;
    } else {
        keyCount = 2;
    }
        
    NSDictionary *uinfo = [NSDictionary dictionaryWithObjects:values forKeys:keys count:keyCount];
    [descr release];
    
    *err = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationError userInfo:uinfo];
    
    return NO; /* Pointless return to appease clang-analyze */
}

static BOOL signatureProcessingFailure(NSError **err, enum OFXMLSignatureOperation op, NSInteger code, NSString *function, NSString *fmt, ...)
{
    if (!err)
        return NO;
    
    va_list varg;
    va_start(varg, fmt);
    NSString *descr = [[NSString alloc] initWithFormat:fmt arguments:varg];
    va_end(varg);
    
    NSString *keys[4];
    id values[4];
    NSUInteger keyCount;
    
    keys[0] = NSLocalizedDescriptionKey;
    values[0] = (op == OFXMLSignature_Verify? @"Failure validating XML signature" : @"Failure creating XML signature");
    
    keys[1] = NSLocalizedFailureReasonErrorKey;
    values[1] = descr;
    
    if (*err) {
        keys[2] = NSUnderlyingErrorKey;
        values[2] = *err;
        keyCount = 3;
    } else {
        keyCount = 2;
    }
    
    if (function) {
        keys[keyCount] = @"function";
        values[keyCount] = function;
        keyCount ++;
    }
    
    NSDictionary *uinfo = [NSDictionary dictionaryWithObjects:values forKeys:keys count:keyCount];
    [descr release];
    
    *err = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:code userInfo:uinfo];
    
    return NO; /* Pointless return to appease clang-analyze */
}
#define signatureValidationFailure(e, ...) signatureProcessingFailure(e, OFXMLSignature_Verify, OFXMLSignatureValidationFailure, nil, __VA_ARGS__)

static BOOL translateLibXMLError(NSError **outError, BOOL asValidation, NSString *fmt, ...)
{
    if (!outError) {
        xmlResetLastError();
        return NO; /* Pointless return to appease clang-analyze */
    }
    
    NSString *userDesc, *libDesc;
    
    {
        va_list varg;
        va_start(varg, fmt);
        userDesc = [[NSString alloc] initWithFormat:fmt arguments:varg];
        va_end(varg);
    }
    
    xmlErrorPtr libxmlErr = xmlGetLastError();
    if (libxmlErr != NULL)
        libDesc = [NSString stringWithFormat:@" (%d, %d): %s", libxmlErr->domain, libxmlErr->code, libxmlErr->message];
    else
        libDesc = @"";
    xmlResetLastError();

    BOOL result;
    if (asValidation)
        result = signatureValidationFailure(outError, @"%@%@", userDesc, libDesc);
    else
        result = signatureStructuralFailure(outError, @"%@%@", userDesc, libDesc);
    
    [userDesc release];

    return result;
}

static BOOL noKeyError(NSError **err, enum OFXMLSignatureOperation op)
{
    if (!err)
        return NO;
    
    if ([[*err domain] isEqualToString:OFXMLSignatureErrorDomain] &&
        [*err code] == OFKeyNotAvailable) {
        return NO;
    }
    
    NSMutableDictionary *uinfo = [NSMutableDictionary dictionary];
    
    switch(op) {
        case OFXMLSignature_Sign:
            [uinfo setObject:@"Failure creating XML signature" forKey:NSLocalizedDescriptionKey];
            [uinfo setObject:@"Private key not available" forKey:NSLocalizedFailureReasonErrorKey];
            break;
        case OFXMLSignature_Verify:
            [uinfo setObject:@"Failure validating XML signature" forKey:NSLocalizedDescriptionKey];
            [uinfo setObject:@"Public key not available"  forKey:NSLocalizedFailureReasonErrorKey];
            break;
    }
    
    if (*err)
        [uinfo setObject:(*err) forKey:NSUnderlyingErrorKey];
    
    *err = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFKeyNotAvailable userInfo:uinfo];
    
    return NO; /* Pointless return to appease clang-analyze */
}

@interface OFXMLSignature ()
/* Private API, to be moved */
- (BOOL)_writeReference:(xmlNode *)reference to:(struct OFXMLSignatureVerifyContinuation *)stream error:(NSError **)outError;

- (BOOL)_prepareTransform:(const xmlChar *)algid :(xmlNode *)transformNode from:(struct OFXMLSignatureVerifyContinuation *)fromBuf error:(NSError **)outError;
@end

@implementation OFXMLSignature

/* Internal utility routines */
static xmlChar *lessBrokenGetAttribute(xmlNode *elt, const char *localName, const xmlChar *nsuri);
static NSString *copyNodeImmediateTextContent(const xmlNode *node);

static BOOL isNamed(const xmlNode *node, const char *nodename, const xmlChar *nsuri, xmlNs **nsCache)
{
    /* Check namespace */
    if (node->ns) {
        if (nsCache && *nsCache && *nsCache == node->ns) {
            /* Namespace matches. */
        } else {
            if (xmlStrcmp(node->ns->href, nsuri) == 0) {
                if (nsCache)
                    *nsCache = node->ns;
                /* Namespace matches. */
            } else {
                /* Namespace does not match. */
                return NO;
            }
        }
    } else {
        return NO;  /* We don't deal with un-namespaced elements anywhere */
    }

    /* Check nodename (local part) */
    if (strcmp((char *)(node->name), nodename) != 0)
        return NO;
    
    return YES;
}

/*" Finds the first immediate child of the 'node' element with the specified name in the specified namespace. If count is non-NULL, returns the total count of matching children in *count. If no child is found, returns NULL (and sets *count to 0). "*/
xmlNode *OFLibXMLChildNamed(const xmlNode *node, const char *nodename, const xmlChar *nsuri, unsigned int *count)
{
    xmlNs *nsCache = NULL;
    xmlNode *result, *cursor;
    
    if (count)
        *count = 0;
    
    result = NULL;
    for(cursor = node->children; cursor; cursor = cursor->next) {
        if (cursor->type != XML_ELEMENT_NODE)
            continue;
        if (isNamed(cursor, nodename, nsuri, &nsCache)) {
            if (!count)
                return cursor;
            else {
                (*count) ++;
                if (!result)
                    result = cursor;
            }
        }
    }
    
    return result;
}

/*" Finds all children of the 'node' element with the specified name in the specified namespace. The caller must free() the returned buffer. The length of the buffer is returned in *count. "*/
xmlNode **OFLibXMLChildrenNamed(const xmlNode *node, const char *nodename, const xmlChar *nsuri, unsigned int *count)
{
    xmlNs *nsCache = NULL;
    xmlNode **result, *cursor;
    unsigned int childCount, childIndex;
    
    childCount = 0;
    for(cursor = node->children; cursor; cursor = cursor->next) {
        if (cursor->type != XML_ELEMENT_NODE)
            continue;
        if (isNamed(cursor, nodename, nsuri, &nsCache))
            childCount ++;
    }
    
    result = malloc( (1+childCount) * sizeof(*result) );
    childIndex = 0;
    for(cursor = node->children; cursor; cursor = cursor->next) {
        if (cursor->type != XML_ELEMENT_NODE)
            continue;
        if (isNamed(cursor, nodename, nsuri, &nsCache))
            result[childIndex++] = cursor;
    }
    
    result[childIndex] = NULL;
    *count = childIndex;
    
    return result;
}


// Apparently *nobody* handles default namespaces on attributes correctly.
static xmlChar *lessBrokenGetAttribute(xmlNode *elt, const char *localName, const xmlChar *nsuri)
{
    xmlAttrPtr result;
    
    result = NULL;
    if (elt->ns && !xmlStrcmp(elt->ns->href, nsuri)) {
        /* The element's namespace is the same as the namespace we're looking for, so check for an unprefixed attribute */
        result = xmlHasProp(elt, (const xmlChar *)localName);
    }
    
    /* Otherwise, fall back on libxml behavior */
    if (!result)
        result = xmlHasNsProp(elt, (const xmlChar *)localName, nsuri);
    
    return xmlNodeGetContent((xmlNode *)result);
}

static NSString *copyNodeImmediateTextContent(const xmlNode *node)
{
    xmlNode *cursor;
    
    for(cursor = node->children; cursor; cursor = cursor->next) {
        if (!(cursor->type == XML_ATTRIBUTE_NODE || cursor->type == XML_COMMENT_NODE))
            break;
    }
    
    if (!cursor)
        return nil;
    
    xmlNode *firstText = cursor;
    
    for(cursor = cursor->next; cursor; cursor = cursor->next) {
        if (!(cursor->type == XML_ATTRIBUTE_NODE || cursor->type == XML_COMMENT_NODE))
            break;
    }
    
    if (xmlNodeIsText(firstText) && !cursor) {
        // Only one text node; just return it.
        return [[NSString alloc] initWithBytes:firstText->content length:xmlStrlen(firstText->content) encoding:NSUTF8StringEncoding];
    }
    
    // Multiple text nodes, or some other complicated situation. Pack stuff into a buffer, then wrap a string around that.
    xmlChar *buf = xmlNodeGetContent((xmlNode *)node);
    return [[NSString alloc] initWithBytesNoCopy:buf length:xmlStrlen(buf) encoding:NSUTF8StringEncoding freeWhenDone:YES];
}

NSData *OFLibXMLNodeBase64Content(const xmlNode *node)
{
    NSString *text = copyNodeImmediateTextContent(node);
    if (!text)
        return nil;
    
    @try {
        return [[[NSData alloc] initWithBase64EncodedString:text options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
    } @finally {
        [text release];
    };
    
    return nil;
}

static int libxmlToNSData_write(void *context, const char *buffer, int len)
{
    if (len < 0)
        return -1;
    [(__bridge NSMutableData *)context appendBytes:buffer length:len];
    return len;
}

static int libxmlToNSData_close(void *context)
{
    OBAutorelease((__bridge NSMutableData *)context);
    return 0;
}

static xmlOutputBuffer *OFLibXMLOutputBufferToData(NSMutableData *destination)
{
    OBStrongRetain(destination);
    
    xmlOutputBuffer *buf = xmlOutputBufferCreateIO(libxmlToNSData_write, libxmlToNSData_close, (__bridge void *)destination, NULL);
    if (!buf) {
        OBStrongRelease(destination);
        return nil;
    } else {
        return buf;
    }
}

static void setNodeContentToBase64Data(xmlNode *node, NSData *rawData)
{
#if (defined(MAC_OS_X_VERSION_10_9) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_9) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 70000)
    NSData *encodedData = [rawData base64EncodedDataWithOptions:0];
    xmlNodeSetContentLen(node, [encodedData bytes], (int)[encodedData length]);
#else
    NSString *encodedData = [rawData base64String];
    xmlNodeSetContent(node, (const xmlChar *)[encodedData cStringUsingEncoding:NSUTF8StringEncoding]);
#endif
}

static int isElementVisible(void *user_data, xmlNode *node)
{
    while(node) {
        if (node == user_data)
            return 1;
        node = node->parent;
    }
    return 0;
}

/* Passed as a callback to xmlC14NExecute() when canonicalizing a node-set defined by a single apex node */ 
static int isOneVisible(void *user_data, xmlNodePtr node, xmlNodePtr parent)
{
    /* We only actually get asked about ELEMENT, ATTRIBUTE, TEXT, and NAMESPACE nodes. In the case of ATTRIBUTES and TEXT, the parent node (which is an element) determines our visibility. In the case of NAMESPACE declarations, we go ahead and mark them all as visible; the canonicalization algorithm strips out unneeded decls. */
    
#ifdef DEBUG_C14N_VISIBILITY
    printf("Asking about %p type=%d ", node, node->type);
    switch(node->type) {
        case XML_ELEMENT_NODE:
            printf("<%s> ", node->name);
            break;
        case XML_ATTRIBUTE_NODE:
            printf("%s=...", node->name);
            break;
        case XML_NAMESPACE_DECL:
            printf("xmlns:%s=\"%s\" ", ((xmlNs *)node)->prefix, ((xmlNs *)node)->href);
            break;
        case XML_TEXT_NODE:
            printf("#TEXT ");
            break;
        default:
            break;
    }
    printf(" parent=%p ", parent);
#endif
    
//    if (node->type == XML_NAMESPACE_DECL)
//        return 1;
    
    int result;
    if (node->type == XML_ELEMENT_NODE)
        result = isElementVisible(user_data, node);
    else
        result = isElementVisible(user_data, parent);
    
#ifdef DEBUG_C14N_VISIBILITY
    printf(" -> %d\n", result);
#endif
    
    return result;
}

static int isOneVisibleOmittingComments(void* user_data, xmlNodePtr node, xmlNodePtr parent)
{
    if (node->type == XML_COMMENT_NODE)
        return 0;
    else
        return isOneVisible(user_data, node, parent);
}

/* This just invokes xmlC14NExecute() on cnode with the options specified by the cmethod node */ 
static BOOL canonicalizeToBuffer(xmlDoc *owningDocument, xmlNode *cNode, xmlNode *cmethod, xmlOutputBuffer *buf, NSError **err)
{
    /* Note: LibXML2 only seems to implement XML C14N 1.0, this is fine for our use but we're not fully conformant if we don't support 1.1 */
    /* TODO: Need to properly distinguish between c14n 1.0 and c14n 1.1 */
    int keepComments, isExclusive;
    enum {
        version_10,
        version_11,
        version_exc_10
    } version;
    const xmlChar **inclusiveNamespacePrefixList;
    
    xmlChar *algid = lessBrokenGetAttribute(cmethod, "Algorithm", XMLSignatureNamespace);
    if (!algid) {
        signatureStructuralFailure(err, @"No canonicalization algorithm specified");
        return NO;
    }
    
    if (xmlStrcmp(algid, XMLCanonicalization10_KeepComments) == 0) {
        keepComments = 1;
        version = version_10;
    } else if (xmlStrcmp(algid, XMLCanonicalization10_OmitComments) == 0) {
        keepComments = 0;
        version = version_10;
    } else if (xmlStrcmp(algid, XMLCanonicalization11_KeepComments) == 0) {
        keepComments = 1;
        version = version_11;
    } else if (xmlStrcmp(algid, XMLCanonicalization11_OmitComments) == 0) {
        keepComments = 0;
        version = version_11;
    } else if (xmlStrcmp(algid, XMLCanonicalizationExc10_KeepComments) == 0) {
        keepComments = 1;
        version = version_exc_10;
    } else if (xmlStrcmp(algid, XMLCanonicalizationExc10_OmitComments) == 0) {
        keepComments = 0;
        version = version_exc_10;
    } else {
        xmlFree(algid);
        signatureValidationFailure(err, @"Unsupported canonicalization method <%s>", algid);
        return NO;
    }
    xmlFree(algid);
    
    if (version == version_exc_10) {
        unsigned int eccount = 0;
        xmlNode *includes = OFLibXMLChildNamed(cmethod, "InclusiveNamespaces", XMLExclusiveCanonicalizationNamespace, &eccount);
        if (eccount > 1) {
            signatureValidationFailure(err, @"Found %d <InclusiveNamespaces> elements", eccount);
            return NO;
        } else if (eccount == 1 && includes) {
            xmlChar *prefixList = lessBrokenGetAttribute(includes, "PrefixList", XMLExclusiveCanonicalizationNamespace);
            if (prefixList != NULL) {
                /* It's easier to roundtrip this through Foundation than to write my own token splitter */
                NSArray<NSString *> *prefixes = [[NSString stringWithCString:(const char *)prefixList encoding:NSUTF8StringEncoding] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                inclusiveNamespacePrefixList = malloc((1+[prefixes count]) * sizeof(*inclusiveNamespacePrefixList));
                unsigned int actualPrefixCount = 0;
                for(NSUInteger prefixIndex = 0; prefixIndex < [prefixes count]; prefixIndex ++) {
                    NSString *onePrefix = [prefixes objectAtIndex:prefixIndex];
                    if (![NSString isEmptyString:onePrefix]) {
                        inclusiveNamespacePrefixList[actualPrefixCount++] = (const xmlChar *)[onePrefix cStringUsingEncoding:NSUTF8StringEncoding];
                    }
                }
                inclusiveNamespacePrefixList[actualPrefixCount] = NULL;
            } else {
                inclusiveNamespacePrefixList = NULL;
            }
        } else {
            inclusiveNamespacePrefixList = NULL;
        }
        isExclusive = 1;
    } else {
        isExclusive = 0;
        inclusiveNamespacePrefixList = NULL;
    }
    
    int ok = xmlC14NExecute(owningDocument, isOneVisible, cNode, isExclusive, (xmlChar **)inclusiveNamespacePrefixList, keepComments, buf);
    
    if (inclusiveNamespacePrefixList)
        free(inclusiveNamespacePrefixList);
    
    if (ok < 0) {
        translateLibXMLError(err, YES, @"XML canonicalization error");
        return NO;
    }
    
    return YES;
}

/* Since we generally don't have a DTD in the document we're processing, libxml doesn't know that the dsig:id attribute is an ID attribute in the XML sense. This function just traverses the document and explicitly marks them all as ID. */
static void fakeSetXmlSecIdAttributeType(xmlDoc *doc, xmlXPathContext *ctxt)
{
    /* We know that the dsig namespace's id attribute is of ID type, but the document might not include a DTD subset indicating that. Sigh. It turns out everybody has this problem --- the specifications are fighting each other. */
    
    /* Only checking the local name, since xpatheval has the usual confusion regarding the default namespace of an attribute */
    /* TODO: See if namespace declarations actually work in libxml2's xpath implementation */
    xmlXPathObject *secIdNodes = xmlXPathEval((const xmlChar *)"//attribute::*[local-name() = 'Id']", ctxt);
    
    /* TODO: use the libxml string interning table for faster comparison? */
    const xmlChar *nsUri = XMLSignatureNamespace;
    
    if (secIdNodes && secIdNodes->type == XPATH_NODESET) {
        xmlNode **nodeTab = secIdNodes->nodesetval->nodeTab;
        int nodeIndex = secIdNodes->nodesetval->nodeNr;
        while(nodeIndex--) {
            xmlNode *oneAttrNode = nodeTab[nodeIndex];
            xmlAttr *oneAttr = (xmlAttr *)oneAttrNode; // overlaid structs
            
            /* Already declared as an ID attribute? */
            if (oneAttr->atype == XML_ATTRIBUTE_ID)
                continue;
            
            /* Figure out the applicable namespace */
            xmlNs *thisNs = oneAttr->ns;
            if (!thisNs)
                thisNs = oneAttr->parent->ns;
            // NSLog(@" %p ns=%p (%s of %s)", oneAttr, oneAttr->ns, thisNs? (char *)(thisNs->href) : "-", oneAttr->parent->name);
            
            /* If not in our desired namespace, don't touch it */
            if (!thisNs || !thisNs->href || !(thisNs->href == nsUri || !xmlStrcmp(thisNs->href, nsUri)))
                continue;
            
            xmlChar *idValue = xmlNodeGetContent(oneAttrNode);
            xmlAddID(NULL, doc, idValue, oneAttr);
            // NSLog(@"  Setting id \"%s\" for node %p", (char *)idValue, oneAttr);
            xmlFree(idValue);
        }
        xmlXPathFreeObject(secIdNodes);
    }
}

/*" Returns an array of OFXMLSignature objects corresponding to the Signature elements in libxmlDocument. Note that each OFXMLSignature object has a reference to this document, so you need to be sure not to deallocate the document tree while the OFXMLSignatures are still live. "*/
+ (NSArray *)signaturesInTree:(xmlDoc *)libxmlDocument
{
    xmlXPathContext *searchContext = xmlXPathNewContext(libxmlDocument);
    xmlXPathObject *signatureNodes = xmlXPathEval((const xmlChar *)"//*[local-name()='Signature' and namespace-uri()='http://www.w3.org/2000/09/xmldsig#']", searchContext);
    
    fakeSetXmlSecIdAttributeType(libxmlDocument, searchContext);
    
    NSMutableArray *result;
    
    if (!signatureNodes || signatureNodes->type != XPATH_NODESET) {
        result = nil;
    } else {
        result = [[NSMutableArray alloc] initWithCapacity:signatureNodes->nodesetval->nodeNr];
        [result autorelease];
        for(int nodeIndex = 0; nodeIndex < signatureNodes->nodesetval->nodeNr; nodeIndex ++) {
            OFXMLSignature *elt = [[self alloc] initWithElement:signatureNodes->nodesetval->nodeTab[nodeIndex] inDocument:libxmlDocument];
            [result addObject:elt];
            [elt release];
        }
    }
    
    if (signatureNodes != NULL)
        xmlXPathFreeObject(signatureNodes);
    xmlXPathFreeContext(searchContext);
    
    return result;
}

// Override the superclass designated initializer to fail
- (instancetype)init;
{
    // Since we set -initWithElement:inDocument: to be the designated initializer, our subclass -init is considered to be a convenience. This will get rejected due to the NULL values
    return [self initWithElement:NULL inDocument:NULL];
}

/*" Designated initializer. sig must be a Signature node in the provided document tree. "*/
- initWithElement:(xmlNode *)sig inDocument:(xmlDoc *)doc
{
    self = [super init];
    
    if (!sig || !doc)
        OBRejectInvalidCall(self, _cmd, @"argument is NULL");
    
    if (!isNamed(sig, "Signature", XMLSignatureNamespace, NULL)) {
        OBRejectInvalidCall(self, _cmd, @"Provided element is not a <Signature> element in the XML DSIG namespace");
    }
    
    originalSignatureElt = sig;
    owningDocument = doc;
    
    return self;
}

- (void)dealloc
{
    if (referenceNodes)
        free(referenceNodes);
    
    xmlFreeDoc(signedInformation);
    
    originalSignatureElt = NULL;
    owningDocument = NULL;
    
    [super dealloc];
}

/*" Verifies the signature on the Signature element. If verification fails, returns NO and sets *err. If it succeeds, the -countOfReferenceNodes and -verifyReferenceAtIndex:toBuffer:error: methods can be used to retrieve and verify the individual signed referents. "*/
- (BOOL)processSignatureElement:(NSError **)err
{
    return [self processSignatureElement:OFXMLSignature_Verify error:err];
}

- (BOOL)processSignatureElement:(enum OFXMLSignatureOperation)op error:(NSError **)err;
{
    OBPRECONDITION(signedInformation == nil);
    if (signedInformation)
        return YES;

    unsigned int count;
    
    // Some data we extract from the <Signature> element
    
    
    /* Note that we're more strict than XMLDSIG requires: we don't allow intermediate nodes of other namespaces here, even though the <Signature> element is only required to be "laxly valid". We are also more lax than XMLDSIG specifies, because we don't require our immediate children to be in any particular order. */
    /* The signature element must contain exactly one SignedInfo and one SignatureValue. It can also contain KeyInfo and Object elements. */    
    
    xmlNode *signedInfo = OFLibXMLChildNamed(originalSignatureElt, "SignedInfo", XMLSignatureNamespace, &count);
    if (count != 1) {
        signatureStructuralFailure(err, @"Found %d <SignedInfo> elements", count);
        return NO;
    }

    xmlNode *signatureValueNode = OFLibXMLChildNamed(originalSignatureElt, "SignatureValue", XMLSignatureNamespace, &count);
    if (count != 1) {
        signatureStructuralFailure(err, @"Found %d <SignatureValue> elements", count);
        return NO;
    }
    NSData *signatureValue = NULL;
    if (op == OFXMLSignature_Verify) {
        signatureValue = OFLibXMLNodeBase64Content(signatureValueNode);
        if (!signatureValue) {
            signatureStructuralFailure(err, @"The <SignatureValue> content is not parsable as base64 data");
            return NO;
        }
    }
    
    xmlNode *keyInfo = OFLibXMLChildNamed(originalSignatureElt, "KeyInfo", XMLSignatureNamespace, &count);
    if (count > 1) {
        signatureStructuralFailure(err, @"Found %d <KeyInfo> elements", count);
        return NO;
    }
    
    /* Canonicalize the <SignedInfo> element and verify that it matches the specified digest */
    
    xmlNode *canonMethodElement = OFLibXMLChildNamed(signedInfo, "CanonicalizationMethod", XMLSignatureNamespace, &count);
    if (count != 1) {
        signatureStructuralFailure(err, @"Found %d <CanonicalizationMethod> elements", count);
        return NO;
    }
    
    NSMutableData *canonicalSignedInfoBytes = [[NSMutableData alloc] init];
    xmlOutputBuffer *canonicalSignedInfoBuf = OFLibXMLOutputBufferToData(canonicalSignedInfoBytes);
    BOOL canonOK = canonicalizeToBuffer(owningDocument, signedInfo, canonMethodElement, canonicalSignedInfoBuf, err);
    
    if (!canonOK) {
    unwind_sibuf:
        xmlOutputBufferClose(canonicalSignedInfoBuf);
    unwind_sibytes:
        [canonicalSignedInfoBytes release];
        return NO;
    }
    
    if (xmlOutputBufferFlush(canonicalSignedInfoBuf) < 0) {
        signatureStructuralFailure(err, @"Unable to canonicalize SignedInfo");
        goto unwind_sibuf;
    }
    
    if (xmlOutputBufferClose(canonicalSignedInfoBuf) < 0) {
        signatureStructuralFailure(err, @"Unable to canonicalize SignedInfo");
        goto unwind_sibytes;
    }
    
    if ([canonicalSignedInfoBytes length] < 1 || [canonicalSignedInfoBytes length] >= INT_MAX) {
        /* The length arg of xmlParseMemory() is an int, not a size_t, so check that the buffer's length is within range */
        signatureStructuralFailure(err, @"Unable to canonicalize SignedInfo");
        goto unwind_sibytes;
    }
    
    /* Always extract values from the canonicalized signature element, since the canonicalized version is what the signature is protecting. See XMLDSIG-CORE [3.2.2], [8.1.3]; and an ongoing series of CERT announcements. */
    xmlDoc *canonicalSignedInfo = xmlParseMemory([canonicalSignedInfoBytes bytes], (int)[canonicalSignedInfoBytes length]);
    if (!canonicalSignedInfo || !isNamed(xmlDocGetRootElement(canonicalSignedInfo), "SignedInfo", XMLSignatureNamespace, NULL)) {
        signatureStructuralFailure(err, @"Unable to parse the canonicalized <SignedInfo>");
        goto unwind_sibytes;
    }
    
    xmlNode *signatureMethod = OFLibXMLChildNamed(xmlDocGetRootElement(canonicalSignedInfo), "SignatureMethod", XMLSignatureNamespace, &count);
    if (count != 1) {
        signatureStructuralFailure(err, @"Found %d <SignatureMethod> elements", count);
    unwind_sidoc:
        xmlFreeDoc(canonicalSignedInfo);
        goto unwind_sibytes;
    }
    
    xmlChar *signatureAlgorithm = lessBrokenGetAttribute(signatureMethod, "Algorithm", XMLSignatureNamespace);
    if (!signatureAlgorithm) {
        signatureStructuralFailure(err, @"No algorithm specified in <SignatureMethod> element");
        goto unwind_sidoc;
    }
    
    BOOL success;

    {
        id <OFDigestionContext, NSObject> verifier = nil;
        @try {
            verifier = [self newVerificationContextForMethod:signatureMethod
                                                     keyInfo:keyInfo
                                                   operation:op
                                                       error:err];
            
            if (!verifier)
                goto failed;
            
            if (op == OFXMLSignature_Verify) {
                success =
                    [verifier verifyInit:err] &&
                    [verifier processBuffer:[canonicalSignedInfoBytes bytes] length:[canonicalSignedInfoBytes length] error:err] &&
                    [verifier verifyFinal:signatureValue error:err];
            } else if (op == OFXMLSignature_Sign) {
                
                if (![verifier generateInit:err])
                    goto failed;
                
                if (![verifier processBuffer:[canonicalSignedInfoBytes bytes] length:[canonicalSignedInfoBytes length] error:err])
                    goto failed;
                
                NSData *generatedSignature = [verifier generateFinal:err];
                if (!generatedSignature)
                    goto failed;

                success = YES;
                setNodeContentToBase64Data(signatureValueNode, generatedSignature);
            } else {
                signatureStructuralFailure(err, @"(bad op %d at line %u)", op, (unsigned)__LINE__);
                success = NO;
            }
            
            if (0) {
            failed:
                success = NO;
            }
        } @catch (NSException *e) {
            success = NO;
            signatureProcessingFailure(err, op, OFXMLSignatureValidationError, nil, @"Exception raised during verification: %@", e);
        } @finally {
            [verifier release];
        };
        
    }
    
    xmlFree(signatureAlgorithm);
    [canonicalSignedInfoBytes release];
    
    if (op == OFXMLSignature_Verify && (success || keepFailedSignatures)) {
        /* w00t, we have a valid signature of... something. */
        signedInformation = canonicalSignedInfo;
        
        /* find and squirrel away all the Reference nodes */
        referenceNodes = OFLibXMLChildrenNamed(xmlDocGetRootElement(canonicalSignedInfo), "Reference", XMLSignatureNamespace, &referenceNodeCount);
    } else {
        xmlFreeDoc(canonicalSignedInfo);
        OBPOSTCONDITION(signedInformation == NULL);
        OBPOSTCONDITION(referenceNodes == NULL);
    }
    
    return success;
}


/*
 A table mapping the XML-DSIG algorithm identifiers to CDSA identifiers or Apple identifiers.
 
 Some notes:
 
 10.7 declares HMACs in the headers, but they're not actually available in the framework. (RADAR 10424173)
 
 Apple's CDSA contains a number of vendor extensions to the standard: CSSM_ALGID_SHA256WithRSA, CSSM_ALGID_SHA512WithRSA, CSSM_ALGID_SHA256WithECDSA, CSSM_ALGID_SHA512WithECDSA.

 SHA1 only has one digest length, so it's specified as 0 in this table (don't want to risk confusing the high-strung Lion crypto APIs with extra information).
 
 The DSA and ECDSA formats require us to know the size of the curve the key uses; for DSA this is fixed at 160 bits, but for EC analogues we need to retrieve it with the key.
*/
static const 
struct algorithmParameter {
    const xmlChar *xmlAlgorithmIdentifier;
    
#if OF_ENABLE_CDSA
    CSSM_ALGORITHMS pk_keytype;
    CSSM_ALGORITHMS pk_signature_alg;
#define PKCALG1(cssmType, cssmUse) CSSM_ALGID_ ## cssmType, CSSM_ALGID_ ## cssmUse,
#define MACALG1(cssmType)          CSSM_ALGID_ ## cssmType, CSSM_ALGID_ ## cssmType,
#else
#define PKCALG1(cssmType, cssmUse) /* */
#define MACALG1(cssmType)          /* */
#endif
    
    // Xcode 7 corrected the type of the values for kSecAttrKeyType to be 'const CFStringRef' instead of 'const CFTypeRef'.
#if defined(MAC_OS_X_VERSION_10_11) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_11
    const CFStringRef   *secKeytype;        /* kSecAttrKeyTypeFoo */
#else
    const CFTypeRef     *secKeytype;        /* kSecAttrKeyTypeFoo */
#endif
    
    const CFStringRef   *secDigestType;     /* kSecDigestFoo */
#define PKCALG2(keytype, digtype) & kSecAttrKeyType ## keytype, & kSecDigest ## digtype,
#define MACALG2(digtype)          NULL, & kSecDigest ## digtype,
    unsigned short       secDigestLength;   /* Length of digest. Use is undocumented except in headers; assuming it's the digest output size in bits, to distinguish the SHA2 family hashes. */
    
    short                fixedWidthSig;     /* 0 if unneeded; >0 for DSA-like algos with a known sig order; <0 for cases where we need to retrieve order with key */
    
    BOOL isHMAC;
} algorithmParameters[] = {
#define PKCALG(name, keyType, fws, cssmUse, hashType, hashLen) { (const xmlChar *)name, PKCALG1( keyType, cssmUse ) PKCALG2( keyType, hashType ) hashLen, fws, NO }
#define MACALG(name, cssmType, digType, digLen)                { (const xmlChar *)name, MACALG1( cssmType ) MACALG2( digType ) digLen, 0, YES }

    PKCALG(XMLPKSignatureDSS,          DSA,   160, SHA1WithDSA,      SHA1, 0),
    
    PKCALG(XMLPKSignaturePKCS1_v1_5,   RSA,     0, SHA1WithRSA,      SHA1, 0),
    PKCALG(XMLPKSignatureRSA_SHA256,   RSA,     0, SHA256WithRSA,    SHA2, 256),
    PKCALG(XMLPKSignatureRSA_SHA512,   RSA,     0, SHA512WithRSA,    SHA2, 512),
    
    PKCALG(XMLPKSignatureECDSA_SHA1,   ECDSA,  -1, SHA1WithECDSA,    SHA1, 0),
    PKCALG(XMLPKSignatureECDSA_SHA256, ECDSA,  -1, SHA256WithECDSA,  SHA2, 256),
    PKCALG(XMLPKSignatureECDSA_SHA512, ECDSA,  -1, SHA512WithECDSA,  SHA2, 512),
    
    /* TODO: Is CSSM_ALGID_RIPEMAC the same algorithm as HMAC-RIPEMD160 ? Check. */
    MACALG(XMLSKSignatureHMAC_SHA1,    SHA1HMAC,    HMACSHA1, 160),
    MACALG(XMLSKSignatureHMAC_MD5,     MD5HMAC,     HMACMD5,  128),
    MACALG(XMLSKSignatureHMAC_SHA256,  NONE,        HMACSHA2, 256),
    MACALG(XMLSKSignatureHMAC_SHA384,  NONE,        HMACSHA2, 384),
    MACALG(XMLSKSignatureHMAC_SHA512,  NONE,        HMACSHA2, 512),
    
#undef PKCALG
#undef MACALG
    { NULL }    
};

/*" Creates and returns a verification context for a given cryptographic algorithm. This method is also in charge of retrieving the key, if any, and checking whether signatures from that key are to be trusted. This is available for subclassing, but this implementation handles DSS-SHA1, HMAC-SHA1/MD5, ECDSA-SHA1/2 and RSA-SHA1/2/MD5. "*/
- (id <OFDigestionContext, NSObject>)newVerificationContextForMethod:(xmlNode *)signatureMethod keyInfo:(xmlNode *)keyInfo operation:(enum OFXMLSignatureOperation)op error:(NSError **)outError;
{
    xmlChar *signatureAlgorithm = lessBrokenGetAttribute(signatureMethod, "Algorithm", XMLSignatureNamespace);
    if (!signatureAlgorithm) {
        signatureStructuralFailure(outError, @"No algorithm specified in <SignatureMethod> element");
        return nil;
    }
    
    const struct algorithmParameter *cursor;
    for (cursor = algorithmParameters; cursor->xmlAlgorithmIdentifier != NULL; cursor ++) {
        if (xmlStrcmp(signatureAlgorithm, cursor->xmlAlgorithmIdentifier) == 0)
            break;
    }
    
    if (cursor->xmlAlgorithmIdentifier == NULL) {
        signatureProcessingFailure(outError, op, OFXMLSignatureValidationFailure, nil, @"Unsupported signature algorithm <%s>", signatureAlgorithm);
        xmlFree(signatureAlgorithm);
        return nil;
    }
    
    xmlFree(signatureAlgorithm);
    
    int sigorder = cursor->fixedWidthSig;
    
    /* Okay, we recognize the algorithm. We can create a verification context for it if we can get a key to use. */
    
    /* First, try to get a SecKeyRef. We can use these with both the 10.4-10.6 and 10.7+ APIs. */
    NSError *keyFindError = nil;
    SecKeyRef keyRef = [self copySecKeyForMethod:signatureMethod keyInfo:keyInfo operation:op error:&keyFindError];
    if (!keyRef && !( [[keyFindError domain] isEqualToString:OFXMLSignatureErrorDomain] && [keyFindError code] == OFKeyNotAvailable )) {
        // If it was a hard failure, pass that back to our caller.
        goto key_find_failure;
    }
    
    if (keyRef && (sigorder < 0)) {
        // We have a SecKeyRef, and we know we need to know its group order, but we don't.
        unsigned blocksize = 0;
        if (OFSecKeyGetAlgorithm(keyRef, NULL, &blocksize, NULL, NULL) != ka_Failure &&
            blocksize > 0 && blocksize <= 16*1024 /* sanity check to avoid crashing securityd - see RADAR 11043986 */ ) {
            sigorder = (int)blocksize;
        }
    }
    
    if (keyRef != NULL) {
        OFSecSignTransform *result = [[OFSecSignTransform alloc] initWithKey:keyRef];
        CFRelease(keyRef);
        result.digestType = *(cursor->secDigestType);
        result.digestLength = cursor->secDigestLength;
        if (sigorder > 0)
            [result setPackDigestsWithGroupOrder:sigorder];
        return result; // We are NS_RETURNS_RETAINED
    }
    
    OBASSERT(keyRef == NULL); // We get here if -copySecKeyForMethod: failed w/o a hard error.
    
    if (keyRef)
        CFRelease(keyRef);
    
#if OF_ENABLE_CDSA
    /* If CDSA is available, then see if we can get a plain CDSA key. */
    OFCSSMKey *key = [self getCSSMKeyForMethod:signatureMethod keyInfo:keyInfo operation:op error:&keyFindError];
    if (!key) {
        goto key_find_failure;
    }
    if (sigorder < 0)
        sigorder = [key groupOrder];
    return [key newVerificationContextForAlgorithm:cursor->pk_signature_alg packDigest:sigorder error:outError];
#endif
    
key_find_failure:
    if (outError) {
        if (keyFindError && [[keyFindError domain] isEqual:OFXMLSignatureErrorDomain]) {
            // Pass this through
            *outError = keyFindError;
        } else {
            noKeyError(&keyFindError, op);
            *outError = keyFindError;
        }
    }
    return nil;
}

static NSData *padInteger(NSData *i, unsigned toLength, NSError **outError)
{
    if (!i)
        return nil;
    NSUInteger iLength = [i length];
    if (iLength < toLength) {
        unsigned char *buf = calloc(toLength, 1);
        [i getBytes:(buf + toLength - iLength) length:iLength];
        return [NSData dataWithBytesNoCopy:buf length:toLength freeWhenDone:YES];
    } else if (iLength == toLength) {
        return i;
    } else {
        signatureStructuralFailure(outError, @"Bignum is %u bytes long, max length is %u bytes", (unsigned)iLength, toLength);
        return nil;
    }
}

// Not using SecAsn1Coder - can't get it to reject certain kinds of corrupt data

#pragma mark Discrete-log signature format conversions

NSData *OFDigestConvertDLSigToPacked(NSData *signatureValue, int integerWidthBits, NSError **outError)
{
    OBASSERT(integerWidthBits > 0);
    
    NSUInteger where = OFASN1UnwrapSequence(signatureValue, outError);
    if (where == ~(NSUInteger)0)
        return nil;
    
    NSData *int1, *int2;
    
    int1 = OFASN1UnwrapUnsignedInteger(signatureValue, &where, outError);
    if (!int1)
        return nil;
    int2 = OFASN1UnwrapUnsignedInteger(signatureValue, &where, outError);
    if (!int2)
        return nil;
    if (where != [signatureValue length]) {
        signatureStructuralFailure(outError, @"Invalid DSA signature (extra data at end of SEQUENCE)");
        return nil;
    }
    
    int integerWidthBytes = ( integerWidthBits + 7 ) / 8;
    
    int1 = padInteger(int1, integerWidthBytes, outError);
    if (!int1)
        return nil;
    int2 = padInteger(int2, integerWidthBytes, outError);
    if (!int2)
        return nil;
    
    return [int1 dataByAppendingData:int2];
}

NSData *OFDigestConvertDLSigToDER(NSData *packedSignature, int integerWidthBits, NSError **outError)
{
    NSUInteger blobLength = [packedSignature length];
    NSUInteger integerWidthBytes;
    
    if (integerWidthBits < 0) {
        /* Not sure how long it should be, but both halves should be the same length */
        if (blobLength & 1) {
            signatureStructuralFailure(outError, @"Invalid DSA signature (length=%u bytes, must be even)", (unsigned int)blobLength);
            return nil;
        }
        integerWidthBytes = blobLength / 2;
    } else {
        integerWidthBytes = ( integerWidthBits + 7 ) / 8;
        if (blobLength != 2*integerWidthBytes) {
            /* The XML-DSIG signature value is simply the concatenation of two RFC2437/PKCS#1 20-byte integers, or other widths for the elliptic-curve analogues. CDSA expects a BER-encoded SEQUENCE of two INTEGERs. */
            signatureStructuralFailure(outError, @"Invalid DSA signature (length=%u bytes, must be %u)", (unsigned int)blobLength, 2*(unsigned)integerWidthBytes);
            return nil;
        }
    }
    
    NSUInteger half = integerWidthBytes;
    NSData *result = [OFASN1CreateForSequence(OFASN1IntegerFromBignum([packedSignature subdataWithRange:(NSRange){   0, half}]),
                                              OFASN1IntegerFromBignum([packedSignature subdataWithRange:(NSRange){half, half}]),
                                              nil) autorelease];
    
    return result;        
}

/*" If -processSignatureElement: returns success, this method indicates the number of references found in the signed information. "*/
- (NSUInteger)countOfReferenceNodes;
{
    if (!referenceNodes)
        OBRejectInvalidCall(self, _cmd, @"Signature element has not been processed yet");
    
    return referenceNodeCount;
}

/* This is the implicit nodes-to-bytes transform which XML-DSIG specifies is inserted into the series of transforms if needed. */
static BOOL implicitC14NTransform(struct OFXMLSignatureVerifyContinuation *continuation, xmlDocPtr doc, xmlC14NIsVisibleCallback is_visible_callback, void *callerCtxt, NSError **outError)
{
    xmlOutputBuffer *stream = (continuation->openStream)(continuation, outError);
    if (!stream)
        return NO;
    
    int ok;
    BOOL result;
    
    ok = xmlC14NExecute(doc, is_visible_callback, callerCtxt, 0, NULL, 1, stream);
    
    /* TODO: Need some way to propagate errors up through xmlC14NExecute() */
    
    if (ok < 0) {
        translateLibXMLError(outError, YES, @"XML canonicalization error");
        result = NO;
    } else {
        result = YES;
    }
    
    ok = xmlOutputBufferClose(stream);
    if (ok < 0) {
        translateLibXMLError(outError, YES, @"Closing XML stream after canonicalization");
        result = NO;
    }
    
    return result;
}

/* This pair of functions implements the enveloped-signature transform. */
/* The context pointer points to the <Signature> node we're omitting. */
struct omitApexForward {
    const xmlNode *omittedNode;
    xmlC14NIsVisibleCallback callerFunction;
    void *callerContext;
};
static int xmlTransformOmitApexCallback(void *user_data, xmlNodePtr node, xmlNodePtr parent)
{
    struct omitApexForward *ctxt = user_data;
    
    /* If the node is the apex of the omitted subtree, or if any of its parents are, then omit it */
    const xmlNode *verboten = ctxt->omittedNode;
    if(node == verboten)
        return 0;
    for(const xmlNode *cursor = parent; cursor; cursor = cursor->parent) {
        if (cursor == verboten)
            return 0;
    }
    
    /* Otherwise, forward the test to the next function */
    return ctxt->callerFunction(ctxt->callerContext, node, parent);
}
static BOOL xmlTransformOmitApex(struct OFXMLSignatureVerifyContinuation *continuation, xmlDocPtr doc, xmlC14NIsVisibleCallback is_visible_callback, void *callerCtxt, NSError **outError)
{
    struct omitApexForward ctxt = (struct omitApexForward){
        .omittedNode = continuation->ctxt,
        .callerFunction = is_visible_callback,
        .callerContext = callerCtxt
    };
    
    return continuation->next->acceptNodes(continuation->next, doc, xmlTransformOmitApexCallback, &ctxt, outError);
}
static xmlOutputBuffer *xmlTransformRejectForeignDoc(struct OFXMLSignatureVerifyContinuation *ctxt_, NSError **outError)
{
    signatureStructuralFailure(outError, @"Enveloped-signature transform can only operate on the original document node set");
    return NULL;
}

/* This is the final "transform" in the sequence; it passes the data to the OFCSSMVerifyContext as well as to the caller. */
/* Verify-and-tee output buffer */
struct verifyAndTeeContext {
    __unsafe_unretained id <OFBufferEater> digester; // Really not retained since it is passed in by our caller
    xmlOutputBuffer *tee;
    __unsafe_unretained NSError *firstError; // Not retained, but we retain/autorelease what we put into this field.
};
static int xmlioVerifyAndTeeWrite(void *context_, const char *buffer, int len)
{
    struct verifyAndTeeContext *context = context_;
    
    if (context->tee) {
        int teed;
        @try {
            teed = xmlOutputBufferWrite(context->tee, len, buffer);
        } @catch (NSException *e) {
            NSLog(@"Exception raised in -verifyReference: %@", e);
            return -1;
        };
        if (teed < 0)
            return teed;
    }
    
    {
        __autoreleasing NSError *error = nil;
        BOOL ok = [context->digester processBuffer:(const unsigned char *)buffer length:len error:&error];
        if (!ok) {
            OBRetainAutorelease(error);
            context->firstError = error;
            return -1;
        }
    }
    
    return len;
}
static xmlOutputBuffer *openTeeStream(struct OFXMLSignatureVerifyContinuation *ctxt_, NSError **outError)
{
    struct verifyAndTeeContext *ctxt = ctxt_->ctxt;

    xmlOutputBuffer *writeTo = xmlOutputBufferCreateIO(xmlioVerifyAndTeeWrite, NULL, ctxt, NULL);
    if (!writeTo) {
        translateLibXMLError(outError, NO, @"Error creating output buffer");
    }
    
    return writeTo;
}

/* This implements the Base64 transform */

struct base64DecodeContext {
    uint8_t buf[4];
    unsigned short buf_used;
    unsigned short EOB;
    xmlOutputBuffer *sink;
};
static const uint8_t b64decode[80] = {
  62, 0xFF, 0xFF, 0xFF, 63,
  52, 53, 54, 55, 56, 57, 58, 59, 60, 61,
  0xFF, 0xFF, 0xFF, 0xFE, 0xFF, 0xFF, 0xFF,
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
  0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
  26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51
};
static int xmlioBase64Decode(void *context_, const char *buffer, int len)
{
    struct base64DecodeContext *context = context_;
    const char *cursor;
    int sinkFail;
    unsigned short buf_used = context->buf_used;
    unsigned short EOB = context->EOB;
    cursor = buffer;
    
    if (EOB && !buf_used) {
        // Discard any data after the termination marker
        return len;
    }
    
    sinkFail = 0;
    while(len > 0 && sinkFail >= 0) {
        unsigned char ch = *cursor;
        cursor++; len--;
        
        if (ch < '+' || ch > 'z') {
            // RFC2045 [6.8]: "Any characters outside of the base64 alphabet are to be ignored"
            continue;
        }
        
        uint8_t chval = b64decode[ch - '+'];
        if (chval & 0x80) {
            if (chval == 0xFF) {
                // Another outside-the-alphabet character
                continue;
            } else if (chval == 0xFE) {
                // An '=', indicating the end of the Base64 data
                chval = 0;
                if (EOB) {
                    // Not the first trailing '='
                } else if (buf_used == 2)
                    EOB = 1;  // Two non-padding chars in the buffer means one decoded char.
                else if (buf_used == 3)
                    EOB = 2;  // Three padding -> two decoded.
                else {
                    // Malformed XML data.
                    // There's apparently no way to report an error from inside an XML output buffer --- the error reporting functions are private to libxml.
                    // This bites, but I guess the hash we're presumably feeding into will catch the error.
                    EOB = 1;
                }
            } else {
                abort(); // Un-possible. 
            }
        }
        
        context->buf[ buf_used ++ ] = chval;
        
        if (buf_used == 4) {
            uint8_t chars[3];
            chars[0] = (context->buf[0] << 2) | (context->buf[1] >> 4);
            chars[1] = (context->buf[1] << 4) | (context->buf[2] >> 2);
            chars[2] = (context->buf[2] << 6) | (context->buf[3]     );
            sinkFail = xmlOutputBufferWrite(context->sink, EOB? EOB : 3, (const char *)chars);
            buf_used = 0;
            if (EOB)
                break;
        }
    }
    
    context->EOB = EOB;
    context->buf_used = buf_used;
    
    if (EOB && !buf_used) // Discard data after termination
        cursor += len;
    
    // Propagate failure indication
    if (sinkFail < 0)
        return sinkFail;
    
    /* We know that this difference will fit into an int because we only advance cursor based on len */
    return (int)(cursor - buffer);
}
static int xmlioBase64Close(void *context_)
{
    struct base64DecodeContext *context = context_;

    if (context->buf_used > 0) {
        xmlioBase64Decode(context_, "====", 4 - context->buf_used);
    }
    
    OBASSERT(context->buf_used == 0);
    
    int xmlOk = xmlOutputBufferClose(context->sink);
    
    free(context);
    
    return xmlOk;
}

/* The base64 transform on a byte stream */
static xmlOutputBuffer *openBase64DecodeStream(struct OFXMLSignatureVerifyContinuation *ctxt, NSError **outError)
{
    xmlOutputBuffer *sink = ctxt->next->openStream(ctxt->next, outError);
    if (!sink)
        return NULL;
    
    struct base64DecodeContext *streamCtxt = malloc(sizeof(struct base64DecodeContext));
    streamCtxt->buf_used = 0;
    streamCtxt->EOB = NO;
    streamCtxt->sink = sink;
    
    xmlOutputBuffer *decoder = xmlOutputBufferCreateIO(xmlioBase64Decode, xmlioBase64Close, streamCtxt, NULL);
    if (!decoder) {
        translateLibXMLError(outError, NO, @"Error creating output buffer");
        free(streamCtxt);
        xmlOutputBufferClose(sink);
        return NULL;
    }
    
    return decoder;
}

/* The base64 transform on a node set */
static BOOL xmlSignatureBase64ExtractText(struct OFXMLSignatureVerifyContinuation *continuation, xmlDocPtr doc, xmlC14NIsVisibleCallback is_visible_callback, void *is_visible_arg, NSError **outError)
{
    xmlOutputBuffer *sink = openBase64DecodeStream(continuation, outError);
    if (!sink)
        return NO;
    
    BOOL success = YES;
    
    /* Traverse the document, skipping anything that the isVisibleCallback tells us isn't visible, and write any text nodes to the sink. */
    const xmlNode *rootElt, *cursor;
    cursor = rootElt = xmlDocGetRootElement(doc);
    for(;;) {
        while(cursor->type == XML_ELEMENT_NODE && cursor->children != NULL)
            cursor = cursor->children;
        
        if (cursor->type == XML_TEXT_NODE || cursor->type == XML_CDATA_SECTION_NODE) {
            if (is_visible_callback == NULL || is_visible_callback(is_visible_arg, (xmlNode *)cursor, cursor->parent)) {
                int ioOk = xmlOutputBufferWrite(sink, xmlStrlen(cursor->content), (const char *)(cursor->content));
                if (ioOk < 0) {
                    translateLibXMLError(outError, YES, @"Error writing Base64 node content");
                    success = NO;
                    break;
                }
            }
        }

        while(cursor->next == NULL) {
            if (cursor == rootElt)
                break; // 1
            cursor = cursor->parent;
        }
        if (cursor == rootElt)
            break; // 2
        
        
        // clang-sa doesn't realize this can't be NULL. We can only get here if the while loop enclosing (1) hits the break. In this case cursor->next was NULL, but cursor is rootElt. This guarantees we'll hit the break at (2) and never reach this line while cursor is NULL. Logged as <http://llvm.org/bugs/show_bug.cgi?id=8590>
        cursor = cursor->next;
        OBASSERT_NOTNULL(cursor);
    }
    
    {
        int ioOk = xmlOutputBufferClose(sink);
        if ((ioOk < 0) && success) {
            translateLibXMLError(outError, YES, @"Error closing Base64 decode stream");
            success = NO;
        }
    }
    
    return success;
}

/* The XPath Filter transform (from the core DSIG spec, not the XPath Filter 2 transform) */
/* The context pointer points to the XPath expression; we need to free it when we're done */
struct xpathFilter {
    xmlXPathContext *filterContext;
    xmlXPathCompExpr *xpathTest;
    xmlC14NIsVisibleCallback callerFunction;
    void *callerContext;
};
static int xmlTransformXPathTest(void *user_data, xmlNodePtr node, xmlNodePtr parent)
{
    struct xpathFilter *ctxt = user_data;
    
    /* Forward the test to the upstream function */
    int inInputSet = ctxt->callerFunction(ctxt->callerContext, node, parent);
    
    if (inInputSet <= 0)
        return inInputSet;
    
    ctxt->filterContext->node = node;
#if defined(LIBXML_VERSION) && (LIBXML_VERSION >= 20627)
    return xmlXPathCompiledEvalToBoolean(ctxt->xpathTest, ctxt->filterContext);
#else
    xmlXPathObject *result = xmlXPathCompiledEval(ctxt->xpathTest, ctxt->filterContext);
    if (result) {
        int boolResult = xmlXPathCastToBoolean(result);
        xmlXPathFreeObject(result);
        return boolResult;
    } else {
        return -1;
    }
#endif
}
static BOOL xmlTransformXPathFilter1(struct OFXMLSignatureVerifyContinuation *continuation, xmlDocPtr doc, xmlC14NIsVisibleCallback is_visible_callback, void *is_visible_arg, NSError **outError)
{
    xmlXPathOrderDocElems(doc);

    struct xpathFilter ctxt = (struct xpathFilter){
        .filterContext = NULL,
        .xpathTest = NULL,
        .callerFunction = is_visible_callback,
        .callerContext = is_visible_arg
    };
    
    ctxt.filterContext = xmlXPathNewContext(doc);
    if (!ctxt.filterContext) {
        translateLibXMLError(outError, NO, @"Could not create XPath context");
        return NO;
    }
    ctxt.xpathTest = xmlXPathCtxtCompile(ctxt.filterContext, continuation->ctxt);
    if (!ctxt.xpathTest) {
        translateLibXMLError(outError, YES, @"Could not compile XPath expression");
        xmlXPathFreeContext(ctxt.filterContext);
        return NO;
    }

    /* TODO: We need to copy the namespaces in scope on the XPath node into the XPath context. Unclear whether we should copy the namespaces in scope on the canonicalized XPath node (seems more correct and safer) or the original document's XPath node (poorly defined and possibly insecure). */
    /* TODO: Implement the here() function. Similar problem as with the namespaces. (Likewise in the interpretation of xpointer URIs in <Reference> nodes.) */
    
    BOOL downstreamOK = continuation->next->acceptNodes(continuation->next, doc, xmlTransformXPathTest, &ctxt, outError);
    
    xmlXPathFreeCompExpr(ctxt.xpathTest);
    xmlXPathFreeContext(ctxt.filterContext);
    
    return downstreamOK;
}
static void xmlTransformXPathFilter1Cleanup(void *ctxt)
{
    // ctxt is a string buffer returned from xmlNodeGetContent()
    free(ctxt);
}

- (BOOL)_verifyReferenceNode:(xmlNode *)referenceNode toBuffer:(xmlOutputBuffer *)outBuf digester:(id <OFBufferEater>)digester error:(NSError **)outError
{
    OBASSERT(isNamed(referenceNode, "Reference", XMLSignatureNamespace, NULL));
    
    unsigned int count;
    xmlNode *transformsNode = OFLibXMLChildNamed(referenceNode, "Transforms", XMLSignatureNamespace, &count);
    if (count > 1) {
        signatureStructuralFailure(outError, @"Found %d <Transforms> nodes", count);
        return NO;
    }
    
    unsigned int transformNodeCount;
    xmlNode **transformNodes;
    
    if (transformsNode) {
        transformNodes = OFLibXMLChildrenNamed(transformsNode, "Transform", XMLSignatureNamespace, &transformNodeCount);
    } else {
        transformNodes = NULL;
        transformNodeCount = 0;
    }
    
    struct OFXMLSignatureVerifyContinuation *continuations = malloc((transformNodeCount+1) * sizeof(*continuations));

    struct verifyAndTeeContext writeContext = {
        .digester = digester,
        .tee = outBuf,
        .firstError = nil,
    };
    continuations[0] = (struct OFXMLSignatureVerifyContinuation){
        .ctxt = &writeContext,
        .next = NULL,
        .openStream = openTeeStream,
        .acceptNodes = NULL,
        .cleanup = NULL,
    };
    unsigned int transformIndex;
    // NSLog(@"Reference %u: %u transforms", (unsigned)nodeIndex, transformNodeCount);
    for(transformIndex = 0; transformIndex < transformNodeCount; transformIndex ++) {
        xmlNode *transformNode = transformNodes[ transformNodeCount - transformIndex - 1 ];
        xmlChar *algid = lessBrokenGetAttribute(transformNode, "Algorithm", XMLSignatureNamespace);
        if (!algid) {
            signatureStructuralFailure(outError, @"No transform algorithm specified for transform %d", transformNodeCount - transformIndex);
            break;
        }
        // NSLog(@"Reference %u, xform %u/%u is \"%s\"", (unsigned)nodeIndex, transformIndex, transformNodeCount, (const char *)algid);
        continuations[transformIndex+1] = (struct OFXMLSignatureVerifyContinuation){
            .ctxt = NULL,
            .next = &( continuations[transformIndex] ),
            .openStream = NULL,
            .acceptNodes = NULL,
            .cleanup = NULL
        };
        BOOL ok = [self _prepareTransform:algid :transformNode
                                     from:&(continuations[transformIndex+1])
                                    error:outError];
        xmlFree(algid);
        if (!ok)
            break;
    }
    if (transformIndex < transformNodeCount) {  /* Cleanup after failure of _prepareTransform */
        while(transformIndex > 0) {
            transformIndex--;
            if (continuations[transformIndex].cleanup != NULL)
                continuations[transformIndex].cleanup( continuations[transformIndex].ctxt );
        }
        free(continuations);
        free(transformNodes);
        return NO;
    }
    
    /* Set up implicit conversions */
    for(transformIndex = 0; transformIndex <= transformNodeCount; transformIndex ++) {
        if (continuations[transformIndex].acceptNodes == NULL && continuations[transformIndex].openStream != NULL)
            continuations[transformIndex].acceptNodes = implicitC14NTransform;
        /* TODO: Also implement the implicit bytes->nodes transform */
    }
    
    /* Actually push the data through the transform sequence */
    BOOL ok = [self _writeReference:referenceNode to:&(continuations[transformNodeCount]) error:outError];
    
    for(transformIndex = 0; transformIndex <= transformNodeCount; transformIndex ++) {
        struct OFXMLSignatureVerifyContinuation *cont = &(continuations[transformNodeCount - transformIndex]);
        if (cont->cleanup != NULL)
            cont->cleanup(cont->ctxt);
    }
    free(continuations);
    free(transformNodes);

    return ok;
}

/*" If -processSignatureElement: returns success, this method can be used to retrieve and verify one of the signed objects. 'outBuf' is optional but if you pass NULL the verified data won't be stored anywhere. Typically you'd want to pass an XML parser context there. "*/
- (BOOL)verifyReferenceAtIndex:(NSUInteger)nodeIndex toBuffer:(xmlOutputBuffer *)outBuf error:(NSError **)outError
{
    if (!referenceNodes)
        OBRejectInvalidCall(self, _cmd, @"Signature element has not been processed yet");
    if (nodeIndex >= referenceNodeCount)
        OBRejectInvalidCall(self, _cmd, @"Reference index (%"PRIuNS") is out of range (count is %u)", (unsigned long)nodeIndex, referenceNodeCount);
    xmlNode *referenceNode = referenceNodes[nodeIndex];
    
    unsigned int count;
    xmlNode *digestMethodNode = OFLibXMLChildNamed(referenceNode, "DigestMethod", XMLSignatureNamespace, &count);
    if (count != 1) {
        signatureStructuralFailure(outError, @"Found %d <DigestMethod> nodes", count);
        return NO;
    }
    xmlNode *digestValueNode = OFLibXMLChildNamed(referenceNode, "DigestValue", XMLSignatureNamespace, &count);
    if (count != 1) {
        signatureStructuralFailure(outError, @"Found %d <DigestValue> nodes", count);
        return NO;
    }
    NSData *digestValue = OFLibXMLNodeBase64Content(digestValueNode);
    if (!digestValue) {
        signatureStructuralFailure(outError, @"The <DigestValue> content is not parsable as base64 data");
        return NO;
    }
    id <OFDigestionContext, NSObject> digester = [self newDigestContextForMethod:digestMethodNode error:outError];
    if (!digester)
        return NO;
    
    if (![digester verifyInit:outError]) {
        [digester release];
        return NO;
    }
    
    BOOL ok = [self _verifyReferenceNode:referenceNode toBuffer:outBuf digester:digester error:outError];
    
    
    if (!ok) {
        [digester release];
        return NO;
    }
    
    /* Finally, we actually verify the digest */
    ok = [digester verifyFinal:digestValue error:outError];
    [digester release];
    
    return ok;
}

/*" Invokes -verifyReferenceAtIndex:toBuffer:error:, accumulating the result in an NSData "*/
- (NSData *)verifiedReferenceAtIndex:(NSUInteger)nodeIndex error:(NSError **)outError;
{
    NSMutableData *nsbuf = [NSMutableData data];
    xmlOutputBuffer *buf = OFLibXMLOutputBufferToData(nsbuf);
    
    BOOL ok = [self verifyReferenceAtIndex:nodeIndex toBuffer:buf error:outError];
    
    xmlOutputBufferClose(buf);
    
    if (ok) {
        return nsbuf;
    } else {
        return nil;
    }
}

/*" Given a pointer to a <Reference> node, computes the node's digest (based on its DigestMethod and any Transforms) and updates the node's DigestValue to match. This is one of the very few methods that can be called before -processSignatureElement: is called. "*/
- (BOOL)computeDigestForNode:(xmlNode *)referenceNode error:(NSError **)outError
{
    OBASSERT(isNamed(referenceNode, "Reference", XMLSignatureNamespace, NULL));
    
    unsigned int count;
    xmlNode *digestMethodNode = OFLibXMLChildNamed(referenceNode, "DigestMethod", XMLSignatureNamespace, &count);
    if (count != 1) {
        signatureStructuralFailure(outError, @"Found %d <DigestMethod> nodes", count);
        return NO;
    }
    id <OFDigestionContext, NSObject> digester = [[self newDigestContextForMethod:digestMethodNode error:outError] autorelease];
    if (!digester)
        return NO;
    
    if (![digester generateInit:outError]) {
        return NO;
    }
    
    BOOL ok = [self _verifyReferenceNode:referenceNode toBuffer:NULL digester:digester error:outError];
    
    if (!ok) {
        return NO;
    }

    NSData *digestValue = [digester generateFinal:outError];
    if (!digestValue) {
        return NO;
    }
        
    xmlNode *digestValueNode = OFLibXMLChildNamed(referenceNode, "DigestValue", XMLSignatureNamespace, &count);
    if (count > 1) {
        signatureStructuralFailure(outError, @"Found %d <DigestValue> nodes", count);
        return NO;
    } else if (count == 0) {
        digestValueNode = xmlNewChild(referenceNode, referenceNode->ns,
                                      (const xmlChar *)"DigestValue",
                                      NULL /* initial content */);
    }
    setNodeContentToBase64Data(digestValueNode, digestValue);

    OBASSERT([digestValue isEqual:OFLibXMLNodeBase64Content(digestValueNode)]);
        
    return YES;
}

/*" Calls -computeDigestForNode:error: on all of the Reference nodes. Note that this does not canonicalize the SignedInfo first, so if your canonicalization transform affects the way digests are computed, they will be computed incorrectly. "*/
- (BOOL)computeReferenceDigests:(NSError **)outError;
{
    unsigned count = 0;
    xmlNode *signedInfo = OFLibXMLChildNamed(originalSignatureElt, "SignedInfo", XMLSignatureNamespace, &count);
    if (count != 1) {
        signatureStructuralFailure(outError, @"Found %d <SignedInfo> elements", count);
        return NO;
    }
    
    unsigned nonCanonicalReferenceNodeCount = 0;
    xmlNode **nonCanonicalReferenceNodes = OFLibXMLChildrenNamed(signedInfo, "Reference", XMLSignatureNamespace, &nonCanonicalReferenceNodeCount);
    
    BOOL success = YES;
    
    for(unsigned nodeIndex = 0; nodeIndex < nonCanonicalReferenceNodeCount; nodeIndex ++) {
        success = [self computeDigestForNode:nonCanonicalReferenceNodes[nodeIndex] error:outError];
        if (!success)
            break;
    }
    
    if (nonCanonicalReferenceNodes)
        free(nonCanonicalReferenceNodes);
    
    return success;
}

/*" Returns YES if the reference node at this index is an intra-document reference (empty URI or only a fragment). "*/
- (BOOL)isLocalReferenceAtIndex:(NSUInteger)nodeIndex;
{
    if (!referenceNodes)
        OBRejectInvalidCall(self, _cmd, @"Signature element has not been processed yet");
    if (nodeIndex >= referenceNodeCount)
        OBRejectInvalidCall(self, _cmd, @"Reference index (%lu) is out of range (count is %u)", (unsigned long)nodeIndex, referenceNodeCount);
    
    xmlChar *refURI = lessBrokenGetAttribute(referenceNodes[nodeIndex], "URI", XMLSignatureNamespace);
    
    BOOL isLocal;
    
    if (refURI == NULL || refURI[0] == 0 || refURI[0] == '#')
        isLocal = YES;
    else
        isLocal = NO;
    
    if (refURI)
        free(refURI);
    
    return isLocal;
}

/*" Creates and returns a digest context for the specified algorithm. Subclassers may override this to add more algorithms. "*/
- (id <OFDigestionContext, NSObject>)newDigestContextForMethod:(xmlNode *)digestMethodNode error:(NSError **)outError;
{
    xmlChar *algid = lessBrokenGetAttribute(digestMethodNode, "Algorithm", XMLSignatureNamespace);
    if (!algid) {
        signatureStructuralFailure(outError, @"No digest algorithm specified");
        return nil;
    }
    
    if (xmlStrcmp(algid, XMLDigestSHA1) == 0) {
        xmlFree(algid);
        return [[OFSHA1DigestContext alloc] init];
    } else if (xmlStrcmp(algid, XMLDigestSHA224) == 0) {
        xmlFree(algid);
        OFCCDigestContext *ctxt = [[OFSHA256DigestContext alloc] init];
        ctxt.outputLength = ( 224 / 8 );
        return ctxt;
    } else if (xmlStrcmp(algid, XMLDigestSHA256) == 0) {
        xmlFree(algid);
        return [[OFSHA256DigestContext alloc] init];
    } else if (xmlStrcmp(algid, XMLDigestSHA384) == 0) {
        xmlFree(algid);
        OFCCDigestContext *ctxt = [[OFSHA512DigestContext alloc] init];
        ctxt.outputLength = ( 384 / 8 );
        return ctxt;
    } else if (xmlStrcmp(algid, XMLDigestSHA512) == 0) {
        xmlFree(algid);
        return [[OFSHA512DigestContext alloc] init];
    } else if (xmlStrcmp(algid, XMLDigestMD5) == 0) {
        xmlFree(algid);
        return [[OFMD5DigestContext alloc] init];
    }
    
    signatureValidationFailure(outError, @"Unimplemented digest algorithm <%s>", algid);
    xmlFree(algid);
    return nil;
}

/* This is here so that it can be subclassed, but subclassers would need to understand our internal OFXMLSignatureVerifyContinuation structure to work right. When/if this is needed, figure out what the API should be. */
- (BOOL)_prepareTransform:(const xmlChar *)algid :(xmlNode *)transformNode
                     from:(struct OFXMLSignatureVerifyContinuation *)fromBuf
                    error:(NSError **)outError
{
    if (xmlStrcmp(algid, XMLEncodingBase64) == 0) {
        fromBuf->openStream = openBase64DecodeStream;
        fromBuf->acceptNodes = xmlSignatureBase64ExtractText;
        return YES;
    }
    
    if (xmlStrcmp(algid, XMLTransformEnveloped) == 0) {
        /* Note that we need to point to the node in the original, pre-canonicalization document, not a node in the canonicalized document fragment that our transformNode is from (that document doesn't even have a <Signature> node). */
        fromBuf->ctxt = originalSignatureElt;
        fromBuf->openStream = xmlTransformRejectForeignDoc;
        fromBuf->acceptNodes = xmlTransformOmitApex;
        return YES;
    }
    
    if (xmlStrcmp(algid, XMLTransformXPath) == 0) {
        unsigned int count;
        xmlNode *xpathNode = OFLibXMLChildNamed(transformNode, "XPath", XMLSignatureNamespace, &count);
        if (count != 1) {
            signatureStructuralFailure(outError, @"Found %u <XPath> nodes in XPath transform", count);
            return NO;
        }
        xmlChar *xpathExpr = xmlNodeGetContent(xpathNode);
        fromBuf->ctxt = xpathExpr;
        fromBuf->openStream = NULL;
        fromBuf->acceptNodes = xmlTransformXPathFilter1;
        fromBuf->cleanup = xmlTransformXPathFilter1Cleanup;
        return YES;
    }
    
    /* TODO: Figure out best way for subclassers to extend this method */
    signatureValidationFailure(outError, @"Unimplemented transform algorithm <%s>", algid);
    return NO;
}

/* This evaluates an XPointer expression which is expected to result in exactly one node, and deals with the error reporting if it doesn't. */
static xmlNode *singleNodeFromXptrExpression(const xmlChar *expr, xmlDocPtr inDocument, xmlNode *hereNode, xmlNode *originNode, NSString *evalwhat, NSError **outError)
{
    xmlXPathContext *xptr = xmlXPtrNewContext(inDocument, NULL, NULL);
    if (!xptr) {
        translateLibXMLError(outError, NO, @"Unable to create XPtr context");
        return NULL;
    }
    
    xmlXPathObject *result = xmlXPtrEval(expr, xptr);
    if (!result) {
        translateLibXMLError(outError, YES, @"%@", evalwhat);
        xmlXPathFreeContext(xptr);
        return NULL;
    }

    xmlNode *resultNode;
    
    if (result->type != XPATH_NODESET) {
        signatureStructuralFailure(outError, @"%@: xptr result has unexpected type (%d)", evalwhat, result->type);
        resultNode = NULL;
    } else if (result->nodesetval->nodeNr == 1) {
        resultNode = result->nodesetval->nodeTab[0];
    } else if (result->nodesetval->nodeNr == 0) {
        signatureStructuralFailure(outError, @"%@: matched nothing", evalwhat);
        resultNode = NULL;
    } else {
        signatureStructuralFailure(outError, @"%@: matched %d nodes!", evalwhat, result->nodesetval->nodeNr);
        resultNode = NULL;
    } 
    
    xmlXPathFreeObject(result);
    xmlXPathFreeContext(xptr);
    return resultNode;
}

/* This is in charge of resolving the <Reference> node and writing its contents to the transform+digest stack. */
- (BOOL)_writeReference:(xmlNode *)referenceNode to:(struct OFXMLSignatureVerifyContinuation *)stream error:(NSError **)outError;
{
    OBASSERT(isNamed(referenceNode, "Reference", XMLSignatureNamespace, NULL));
    
    xmlChar *refURI = lessBrokenGetAttribute(referenceNode, "URI", XMLSignatureNamespace);
    NSString *refURIString = refURI? [NSString stringWithCString:(const char *)refURI encoding:NSUTF8StringEncoding] : nil;
    
    /* We handle intra-document references ourselves. Others get handled by our subclass. */
    if (refURI && (*refURI == '#')) {
#if DEBUG
#warning Not handling 'here()'
#endif
        /* TODO: Nontrivial to handle "here" because our reference node is from the transformed, canonicalized SignedInfo, but we need to evaluate the XPointer expression against the original document */
        /* TODO: Make sure we DTRT if the xpointer points to an attribute or something? */
        xmlNode *resultNode = singleNodeFromXptrExpression(refURI+1, owningDocument, NULL, NULL, [NSString stringWithFormat:@"Evaluating <Reference URI=\"%@\">", refURIString], outError);
        
        xmlFree(refURI);

        if (!resultNode) {
            return NO;
        }
        
        BOOL ok = stream->acceptNodes(stream, owningDocument, isOneVisibleOmittingComments, resultNode, outError);
        
        return ok;
    } else if ([NSString isEmptyString:refURIString]) {
        /* This is equivalent to an intra-document reference to the root element */
        if (refURI)
            free(refURI);
        return stream->acceptNodes(stream, owningDocument, isOneVisibleOmittingComments, xmlDocGetRootElement(owningDocument), outError);
    } else {
        xmlChar *refType = lessBrokenGetAttribute(referenceNode, "Type", XMLSignatureNamespace);
        NSString *refTypeString = refType? [NSString stringWithCString:(const char *)refType encoding:NSUTF8StringEncoding] : nil;
        xmlFree(refType);
        xmlFree(refURI);
        
        xmlOutputBuffer *byteStream = (stream->openStream)(stream, outError);
        if (!byteStream)
            return NO;
        
        BOOL ok;
        @try {
            ok = [self writeReference:refURIString type:refTypeString to:byteStream error:outError];
        } @catch (NSException *e) {
            signatureValidationFailure(outError, @"Exception raised during verification: %@", e);
            ok = NO;
        };
        
        int libXmlOk = xmlOutputBufferClose(byteStream);
        if (ok && (libXmlOk < 0)) {
            translateLibXMLError(outError, YES, @"Closing output stream after canonicalization");
            ok = NO;
        }
        
        return ok;
    }
}

#pragma mark Stub implementations of subclass methods

/*
 The key methods are completely stubbed because they really have two responsibilities: one is to find the key, and the other is to evaluate whether it should be trusted for this particular application. I don't envision any use cases where it's useful to distinguish between "this was signed with an untrusted key" and "this was signed with an unknown key", so I'm conflating those here. The trust issue is entirely application-dependent, so the generic superclass defaults to trusting nothing.
*/

#if OF_ENABLE_CDSA
/*" Subclassers must implement this to find and return the specified asymmetric (RSA or DSA) key. "*/
- (OFCSSMKey *)getCSSMKeyForMethod:(xmlNode *)signatureMethod keyInfo:(xmlNode *)keyInfo operation:(enum OFXMLSignatureOperation)op error:(NSError **)outError;
{
    noKeyError(outError, op);
    return nil;
}
#endif /* OF_ENABLE_CDSA */

- (SecKeyRef)copySecKeyForMethod:(xmlNode *)signatureMethod keyInfo:(xmlNode *)keyInfo operation:(enum OFXMLSignatureOperation)op error:(NSError **)outError;
{
    noKeyError(outError, op);
    return NULL;
}

/*" Subclassers must implement this to resolve any external references (that is, <Reference> nodes pointing outside of the containing document). By default, those references are not resolved. "*/
- (BOOL)writeReference:(NSString *)externalReference type:(NSString *)referenceType to:(xmlOutputBuffer *)stream error:(NSError **)outError;
{
    signatureValidationFailure(outError, @"Retrieval of external reference <%@> not supported", externalReference);
    return NO;
}

@end

#pragma mark Key extraction utility functions

/*" This is not a fully featured extraction of the <X509Data> node; it does not return errors, and refuses to parse some valid but weird structures. Returns a dictionary whose keys are the XML element names with the "X509" prefix removed, and whose values are NSStrings or NSDatas, depending on what makes sense for that element. The <X509SerialNumber> subelement of the <X509IssuerSerial> element is returned under the key IssuerSerialNumber. The <X509Certificate> element may be repeated; the value of the Certificate key is always an NSArray. "*/
NSDictionary *OFXMLSigParseX509DataNode(xmlNode *x509Data)
{
    if (!x509Data)
        return nil;
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    xmlNs *nsCache = NULL;
    
    for(xmlNode *cursor = x509Data->children; cursor != x509Data->next; cursor = cursor->next? cursor->next : cursor->parent->next) {
        if (cursor->type != XML_ELEMENT_NODE)
            continue;
        
        NSString *key = nil;
        id value;
        
        if (isNamed(cursor, "X509IssuerSerial", XMLSignatureNamespace, &nsCache)) {
            cursor = cursor->children;
            continue;
        } else if (isNamed(cursor, "X509IssuerName", XMLSignatureNamespace, &nsCache)) {
            value = copyNodeImmediateTextContent(cursor);
        } else if (isNamed(cursor, "X509SerialNumber", XMLSignatureNamespace, &nsCache)) {
            value = copyNodeImmediateTextContent(cursor);
            key = [@"IssuerSerialNumber" retain];
        } else if (isNamed(cursor, "X509SubjectName", XMLSignatureNamespace, &nsCache)) {
            value = copyNodeImmediateTextContent(cursor);
        } else if (isNamed(cursor, "X509SKI", XMLSignatureNamespace, &nsCache)) {
            value = [OFLibXMLNodeBase64Content(cursor) copy];
        } else if (isNamed(cursor, "X509Certificate", XMLSignatureNamespace, &nsCache)) {
            value = [OFLibXMLNodeBase64Content(cursor) copy];
        } else if (isNamed(cursor, "X509CRL", XMLSignatureNamespace, &nsCache)) {
            value = [OFLibXMLNodeBase64Content(cursor) copy];
        } else {
            continue;
        }
        
        // Treat an empty element the same as an absent element.
        if (!value)
            continue;
        
        if (!key) {
            const xmlChar *nodeName = cursor->name;
            OBASSERT(memcmp(nodeName, "X509", 4) == 0);
            key = [[NSString alloc] initWithCString:(const char *)nodeName+4 encoding:NSUTF8StringEncoding];
        }
        
        if ([key isEqualToString:@"Certificate"]) {
            if ([dict objectForKey:key])
                [[dict objectForKey:key] addObject:value];
            else
                [dict setObject:[NSMutableArray arrayWithObject:value] forKey:key];
        } else {
            // Duplicate entries other than X509Certificate are allowed by the spec, but we don't handle them. Bail.
            if ([dict objectForKey:key]) {
                [key release];
                [value release];
                return nil;
            }
            [dict setObject:value forKey:key];
        }
        
        [key release];
        [value release];
    }
    
    return dict;
}

#if OF_ENABLE_CDSA
CSSM_ALGORITHMS OFXMLCSSMKeyTypeForAlgorithm(xmlNode *signatureMethod)
{
    xmlChar *signatureAlgorithm = lessBrokenGetAttribute(signatureMethod, "Algorithm", XMLSignatureNamespace);
    if (!signatureAlgorithm) {
        return NO;
    }
    
    const struct algorithmParameter *cursor;
    for (cursor = algorithmParameters; cursor->xmlAlgorithmIdentifier != NULL; cursor ++) {
        if (xmlStrcmp(signatureAlgorithm, cursor->xmlAlgorithmIdentifier) == 0)
            break;
    }
    
    xmlFree(signatureAlgorithm);
    
    if (cursor->xmlAlgorithmIdentifier)
        return cursor->pk_keytype;
    else
        return CSSM_ALGID_NONE;
}
#endif


#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
/* On Lion, keys are retrieved by passing a dictionary of attributes to SecItemCopyMatching(). Since we already have a mapping from XML-DSIG identifiers to algorithm properties, here's a utility function which stores some key attributes in a dictionary if they can be deduced from the signature+algorithm node. */
BOOL OFXMLSigGetKeyAttributes(NSMutableDictionary *keyusage, xmlNode *signatureMethod, enum OFXMLSignatureOperation op)
{
    xmlChar *signatureAlgorithm = lessBrokenGetAttribute(signatureMethod, "Algorithm", XMLSignatureNamespace);
    if (!signatureAlgorithm) {
        return NO;
    }
    
    const struct algorithmParameter *cursor;
    for (cursor = algorithmParameters; cursor->xmlAlgorithmIdentifier != NULL; cursor ++) {
        if (xmlStrcmp(signatureAlgorithm, cursor->xmlAlgorithmIdentifier) == 0)
            break;
    }
    
    xmlFree(signatureAlgorithm);
    
    if (!cursor->xmlAlgorithmIdentifier)
        return NO;
    
    if (!cursor->isHMAC) { // Asymmetric key
        [keyusage setObject:(id)kSecClassKey forKey:(id)kSecClass];
        [keyusage setObject:(__bridge id)*(cursor->secKeytype) forKey:(id)kSecAttrKeyType];
        /* Why does it matter what the digest type and length is? Because a key usable with (eg) SHA256 might or might not be usable with SHA256 */
        [keyusage setObject:(__bridge id)*(cursor->secDigestType) forKey:(id)kSecDigestTypeAttribute];
        if (cursor->secDigestLength != 0) {
            int digestLengthInt = cursor->secDigestLength;
            CFNumberRef digestLength = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &digestLengthInt);
            [keyusage setObject:(__bridge id)digestLength forKey:(id)kSecDigestLengthAttribute];
            CFRelease(digestLength);
        }
        if (op == OFXMLSignature_Sign) {
            [keyusage setObject:(id)kCFBooleanTrue forKey:(id)kSecAttrCanSign];
            // This is stupid: you have to specify whether it's a private or public key, *as well as* the operation you want to perform with it (sign or verify).
            // (It's also undocumented; but see _CreateSecItemParamsFromDictionary() and _ConvertItemClass() in SecItem.cpp in libsecurity_keychain-55029) */
            [keyusage setObject:(id)kSecAttrKeyClassPrivate forKey:(id)kSecAttrKeyClass];
        } else if (op == OFXMLSignature_Verify) {
            [keyusage setObject:(id)kCFBooleanTrue forKey:(id)kSecAttrCanVerify];
            [keyusage setObject:(id)kSecAttrKeyClassPublic forKey:(id)kSecAttrKeyClass];
        }
        
        return YES;
    } else {
        [keyusage setObject:(__bridge id)*(cursor->secDigestType) forKey:(id)kSecDigestTypeAttribute];
#if 0
        // The truncation length could be a part of the key's attributes, but there's no key to store it under, so I guess it isn't.
        unsigned int count = 0;
        xmlNode *truncation = OFLibXMLChildNamed(signatureMethod, "HMACOutputLength", XMLSignatureNamespace, &count);
        if (count > 1) {
            signatureStructuralFailure(outError, @"Multiple <HMACOutputLength> elements");
            return nil;
        } else if (count == 1) {
            NSString *len = copyNodeImmediateTextContent(truncation);
            if (!len) {
                signatureStructuralFailure(outError, @"Empty <HMACOutputLength> element");
                return nil;
            }
            int specifiedDigestLength = [len intValue];
            [len release];
            
            if (specifiedDigestLength < 1 || specifiedDigestLength > cursor->secDigestLength) {
                signatureStructuralFailure(outError, @"HMACOutputLength=%d, which makes no sense for <%s>", specifiedDigestLength, signatureAlgorithm);
                return nil;
            }
        }
#endif
        if (cursor->secDigestLength != 0) {
            [keyusage setObject:@(cursor->secDigestLength) forKey:(id)kSecDigestLengthAttribute];
        }
        if (op == OFXMLSignature_Sign)
            [keyusage setObject:@YES forKey:(id)kSecAttrCanSign];
        else if (op == OFXMLSignature_Verify)
            [keyusage setObject:@YES forKey:(id)kSecAttrCanVerify];
        [keyusage setObject:(id)kSecAttrKeyClassSymmetric forKey:(id)kSecAttrKeyClass];
        return YES;
    }
}
#endif
