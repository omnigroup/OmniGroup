// Copyright 2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// http://www.omnigroup.com/DeveloperResources/OmniSourceLicense.html.

#import "OFXMLSignature.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFCDSAUtilities.h>

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

NSString *OFXMLSignatureErrorDomain = @"com.omnigroup.OmniFoundation";

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

static BOOL signatureValidationFailure(NSError **err, NSString *fmt, ...)
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
    values[0] = @"Failure validating XML signature";
    
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
    
    *err = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationFailure userInfo:uinfo];
    
    return NO; /* Pointless return to appease clang-analyze */
}

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
    [userDesc autorelease];
    
    xmlErrorPtr libxmlErr = xmlGetLastError();
    if (libxmlErr != NULL)
        libDesc = [NSString stringWithFormat:@" (%d, %d): %s", libxmlErr->domain, libxmlErr->code, libxmlErr->message];
    else
        libDesc = @"";
    xmlResetLastError();

    if (asValidation)
        return signatureValidationFailure(outError, @"%@%@", userDesc, libDesc);
    else
        return signatureStructuralFailure(outError, @"%@%@", userDesc, libDesc);
}

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
        return [NSData dataWithBase64String:text];
    } @finally {
        [text release];
    };
    
    return nil;
}

static void setNodeContentToString(xmlNode *node, NSString *toString)
{
    xmlNodeSetContent(node, (const xmlChar *)[toString cStringUsingEncoding:NSUTF8StringEncoding]);
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
                NSArray *prefixes = [[NSString stringWithCString:(const char *)prefixList encoding:NSUTF8StringEncoding] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
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
            signatureStructuralFailure(err, @"The <SignatureValue> content is not parsable as base64 data", count);
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
    
    xmlOutputBuffer *canonicalSignedInfoBuf = xmlAllocOutputBuffer(NULL);
    BOOL canonOK = canonicalizeToBuffer(owningDocument, signedInfo, canonMethodElement, canonicalSignedInfoBuf, err);
    
    if (!canonOK) {
    unwind_sibuf:
        xmlOutputBufferClose(canonicalSignedInfoBuf);
        return NO;
    }
    
    if ((xmlOutputBufferFlush(canonicalSignedInfoBuf) < 0 ) || !canonicalSignedInfoBuf->buffer->use) {
        signatureStructuralFailure(err, @"Unable to canonicalize SignedInfo");
        goto unwind_sibuf;
    }

    /* Where possible, extract values from the canonicalized signature element, since the canonicalized version is what the signature is protecting. See XMLDSIG-CORE [3.2.2], [8.1.3]. */
    xmlDoc *canonicalSignedInfo = xmlParseMemory((const char *)xmlBufferContent(canonicalSignedInfoBuf->buffer), xmlBufferLength(canonicalSignedInfoBuf->buffer));
    if (!canonicalSignedInfo || !isNamed(xmlDocGetRootElement(canonicalSignedInfo), "SignedInfo", XMLSignatureNamespace, NULL)) {
        signatureStructuralFailure(err, @"Unable to parse the canonicalized <SignedInfo>");
        goto unwind_sibuf;
    }
    
    xmlNode *signatureMethod = OFLibXMLChildNamed(xmlDocGetRootElement(canonicalSignedInfo), "SignatureMethod", XMLSignatureNamespace, &count);
    if (count != 1) {
        signatureStructuralFailure(err, @"Found %d <SignatureMethod> elements", count);
    unwind_sidoc:
        xmlFreeDoc(canonicalSignedInfo);
        goto unwind_sibuf;
    }
    
    xmlChar *signatureAlgorithm = lessBrokenGetAttribute(signatureMethod, "Algorithm", XMLSignatureNamespace);
    if (!signatureAlgorithm) {
        signatureStructuralFailure(err, @"No algorithm specified in <SignatureMethod> element");
        goto unwind_sidoc;
    }
    
    BOOL success;

    {
        id <OFCSSMDigestionContext, NSObject> verifier = nil;
        @try {
            verifier = [self newVerificationContextForAlgorithm:signatureAlgorithm
                                                            method:signatureMethod
                                                           keyInfo:keyInfo
                                                         operation:op
                                                             error:err];
            
            if (!verifier)
                goto failed;
            
            CSSM_DATA cssmBuffer = (CSSM_DATA){
                .Data = canonicalSignedInfoBuf->buffer->content,
                .Length = canonicalSignedInfoBuf->buffer->use
            };
            
            if (op == OFXMLSignature_Verify) {
                NSData *alteredSignatureValue = [self signatureForStoredValue:signatureValue algorithm:signatureAlgorithm method:signatureMethod error:err];
                if (!alteredSignatureValue)
                    goto failed;
                success =
                    [verifier verifyInit:err] &&
                    [verifier processBuffers:&cssmBuffer count:1 error:err] &&
                    [verifier verifyFinal:alteredSignatureValue error:err];
            } else if (op == OFXMLSignature_Sign) {
                
                if (![verifier generateInit:err])
                    goto failed;
                
                if (![verifier processBuffers:&cssmBuffer count:1 error:err])
                    goto failed;
                
                NSData *generatedSignature = [verifier generateFinal:err];
                if (!generatedSignature)
                    goto failed;
                
                NSData *storedSignature = [self storedValueForSignature:generatedSignature algorithm:signatureAlgorithm method:signatureMethod error:err];
                if (!storedSignature)
                    goto failed;
                
                success = YES;
                setNodeContentToString(signatureValueNode, [storedSignature base64String]);
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
            signatureValidationFailure(err, @"Exception raised during verification: %@", e);
        } @finally {
            [verifier release];
        };
        
    }
    
    xmlFree(signatureAlgorithm);
    xmlOutputBufferClose(canonicalSignedInfoBuf);
    
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

/*" Creates and returns a verification context for a given cryptographic algorithm. This method is also in charge of retrieving the key, if any. This is available for subclassing, but this implementation handles DSS-SHA1, HMAC-SHA1/MD5, and RSA-SHA1. "*/
- (id <OFCSSMDigestionContext, NSObject>)newVerificationContextForAlgorithm:(const xmlChar *)signatureAlgorithm method:(xmlNode *)signatureMethod keyInfo:(xmlNode *)keyInfo operation:(enum OFXMLSignatureOperation)op error:(NSError **)outError CLANG_RETURNS_NS_RETAINED
{
    CSSM_ALGORITHMS pk_keytype = CSSM_ALGID_NONE;
    CSSM_ALGORITHMS pk_signature_alg = CSSM_ALGID_NONE;
    if (xmlStrcmp(signatureAlgorithm, XMLPKSignatureDSS) == 0) {
        pk_keytype = CSSM_ALGID_DSA;
        pk_signature_alg = CSSM_ALGID_SHA1WithDSA;
    } else if (xmlStrcmp(signatureAlgorithm, XMLPKSignaturePKCS1_v1_5) == 0) { /* RSA+SHA1 */
        pk_keytype = CSSM_ALGID_RSA;
        pk_signature_alg = CSSM_ALGID_SHA1WithRSA;
    }
    
    if (pk_keytype != CSSM_ALGID_NONE) {
        OFCSSMKey *key;
        switch(op) {
            case OFXMLSignature_Verify:
                key = [self getPublicKey:keyInfo algorithm:pk_keytype error:outError];
                break;
            case OFXMLSignature_Sign:
                key = [self getPrivateKey:keyInfo algorithm:pk_keytype error:outError];
                break;
            default:
                OBRejectInvalidCall(self, _cmd, @"Invalid operation=%d", op);
                key = nil;
                break;
        }
        if (!key) {
            if (outError && ![[*outError domain] isEqual:OFXMLSignatureErrorDomain])
                *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationFailure userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"Key not available", NSLocalizedDescriptionKey, *outError, NSUnderlyingErrorKey, nil]];
            return nil;
        }
        
        OFCDSAModule *thisCSP = [self cspForKey:key];
        
        CSSM_CC_HANDLE context = CSSM_INVALID_HANDLE;
        CSSM_RETURN err = CSSM_CSP_CreateSignatureContext([thisCSP handle], pk_signature_alg, [key credentials], [key key], &context);
        if (err != CSSM_OK || context == CSSM_INVALID_HANDLE) {
            OFErrorFromCSSMReturn(outError, err, @"CSSM_CSP_CreateSignatureContext");
            return nil;
        }
        
        return [[OFCSSMSignatureContext alloc] initWithCSP:thisCSP cc:context];
    }
    
    /* TODO: Is CSSM_ALGID_RIPEMAC the same algorithm as HMAC-RIPEMD160 ? Check. */
    CSSM_ALGORITHMS hmac_algid;
    if ((xmlStrcmp(signatureAlgorithm, XMLSKSignatureHMAC_SHA1) == 0 && (hmac_algid = CSSM_ALGID_SHA1HMAC)) ||
        (xmlStrcmp(signatureAlgorithm, XMLSKSignatureHMAC_MD5) == 0 && (hmac_algid = CSSM_ALGID_MD5HMAC))) {
        unsigned int count = 0;
        OFLibXMLChildNamed(signatureMethod, "HMACOutputLength", XMLSignatureNamespace, &count);
        if (count != 0) {
            signatureStructuralFailure(outError, @"Apple CDSA does not support <HMACOutputLength>");
            return nil;
        }
        
        OFCSSMKey *key = [self getHMACKey:keyInfo algorithm:hmac_algid error:outError];
        if (!key)
            return nil;
        
        OFCDSAModule *thisCSP = [self cspForKey:key];

        CSSM_CC_HANDLE context = CSSM_INVALID_HANDLE;
        CSSM_RETURN err = CSSM_CSP_CreateMacContext([thisCSP handle], hmac_algid, [key key], &context);
        if (err != CSSM_OK || context == CSSM_INVALID_HANDLE) {
            OFErrorFromCSSMReturn(outError, err, @"CSSM_CSP_CreateMacContext");
            return nil;
        }
        
        return [[OFCSSMMacContext alloc] initWithCSP:thisCSP cc:context];
    }
    
    signatureValidationFailure(outError, @"Unsupported signature algorithm <%s>", signatureAlgorithm);
    return nil;
}

static NSData *padInteger(NSData *i, unsigned toLength, NSError **outError)
{
    if (!i)
        return nil;
    NSUInteger iLength = [i length];
    if (iLength < toLength) {
        unsigned char buf[toLength];
        memset(buf, 0, toLength);
        [i getBytes:(buf + toLength - iLength)];
        return [NSData dataWithBytes:buf length:toLength];
    } else if (iLength == toLength) {
        return i;
    } else {
        signatureStructuralFailure(outError, @"Bignum is %u bytes long, max length is %u bytes", (unsigned)iLength, toLength);
        return nil;
    }
}

#if 0  // Not using SecAsn1Coder - can't get it to reject certain kinds of corrupt data

/* Apple's SecAsn1Coder is not very well documented, but it turns out to be Netscape's NSS coder with the serial numbers filed off and a few tweaks (eg, SecItem -> CSSM_DATA) */

struct OFXMLSignatureDSASig {
    CSSM_DATA r;
    CSSM_DATA s;
};

static const SecAsn1Template dsaSignatureTemplate[] =
{
    {
    /* The ASN.1 decoder seems to reuse the CONSTRUCTED bit for some internal purpose. Technically we need to set it, since SEQUENCEs are CONSTRUCTED, right? But if we do, it parses the sequence as a blob, and not its contents. If we don't set it, then the decoder goes ahead and decodes the contained fields. Inspecting the source reveals that the decoder goes ahead and adds CONSTRUCTED to SEQUENCEs after making other decisions based on that flag. (This kind of thing is why I'm not sure I should be using the NSS API instead of rolling my own...) */
        .kind = SEC_ASN1_SEQUENCE /* | SEC_ASN1_CONSTRUCTED */ | SEC_ASN1_UNIVERSAL,
        .offset = 0,
        .sub = NULL, // SEC_ASN1_GROUP not specified, so this is inline
        .size = 0 // sizeof(struct OFXMLSignatureDSASig)
    },
    {
        .kind = SEC_ASN1_INTEGER | SEC_ASN1_UNIVERSAL,
        .offset = offsetof(struct OFXMLSignatureDSASig, r),
        .sub = NULL,
        .size = sizeof(CSSM_DATA) // not actually used
    },
    {
        .kind = SEC_ASN1_INTEGER | SEC_ASN1_UNIVERSAL,
        .offset = offsetof(struct OFXMLSignatureDSASig, s),
        .sub = NULL,
        .size = sizeof(CSSM_DATA) // not actually used
    },
    { .kind = 0 } // sentinel
};

#endif

/*" This method converts the signatureValue from the form it appears in an XML signature to the form expected by the verification object's -verifyFinal:error: method. (It's a no-op for algorithms other than DSS-SHA1, but subclassers may have other behavior.) "*/
- (NSData *)signatureForStoredValue:(NSData *)signatureValue algorithm:(const xmlChar *)signatureAlgorithm method:(xmlNode *)signatureMethod error:(NSError **)outError
{
    // The only algorithm for which XML DSIG varies from the CDSA format is DSS.
    if (xmlStrcmp(signatureAlgorithm, XMLPKSignatureDSS) == 0) {
        /* The XML-DSIG signature value is simply the concatenation of two RFC2437/PKCS#1 20-byte integers. CDSA expects a BER-encoded SEQUENCE of two INTEGERs. */
        if ([signatureValue length] != 40) { /* Magic number 40, from xmldsig-core [6.4.1] */
            signatureStructuralFailure(outError, @"Invalid DSS signature (length=%u bytes, must be 40)", (unsigned int)[signatureValue length]);
            return nil;
        }
        
        NSData *result = [OFASN1CreateForSequence(OFASN1IntegerFromBignum([signatureValue subdataWithRange:(NSRange){ 0, 20}]),
                                                  OFASN1IntegerFromBignum([signatureValue subdataWithRange:(NSRange){20, 20}]),
                                                  nil) autorelease];
        
        OBASSERT([signatureValue isEqual:[self storedValueForSignature:result algorithm:signatureAlgorithm method:signatureMethod error:NULL]]);
        
        return result;        
    }
    
    return signatureValue;
}

/*" This method converts the signatureValue from the form it's returned in from -generateFinal: into the form in which it should be stored in an XML signature. (It's the inverse of -signatureForStoredValue:algorithm:method:error:.) "*/
- (NSData *)storedValueForSignature:(NSData *)signatureValue algorithm:(const xmlChar *)signatureAlgorithm method:(xmlNode *)signatureMethod error:(NSError **)outError
{
    // The only algorithm for which XML DSIG varies from the CDSA format is DSS.
    if (xmlStrcmp(signatureAlgorithm, XMLPKSignatureDSS) == 0) {
        /* The XML-DSIG signature value is simply the concatenation of two RFC2437/PKCS#1 20-byte integers. CDSA produces a BER-encoded SEQUENCE of two BER-encoded INTEGERs. */
        
        NSUInteger where = OFASN1UnwrapSequence(signatureValue, outError);
        if (where == ~(NSUInteger)0)
            return nil;
        
        NSData *int1, *int2;
        
        int1 = padInteger(OFASN1UnwrapUnsignedInteger(signatureValue, &where, outError), 20, outError);
        if (!int1)
            return nil;
        int2 = padInteger(OFASN1UnwrapUnsignedInteger(signatureValue, &where, outError), 20, outError);
        if (!int2)
            return nil;
        
        if (where != [signatureValue length]) {
            signatureStructuralFailure(outError, @"Invalid DSS signature (extra data at end of SEQUENCE)");
            return nil;
        }
        
        // NSLog(@"%@ -> %@, %@", signatureValue, int1, int2);
        
        return [int1 dataByAppendingData:int2];
    }
    
    return signatureValue;
}

- (OFCDSAModule *)cspForKey:(OFCSSMKey *)aKey;
{
    OFCDSAModule *keyCSP = [aKey csp];
    if (keyCSP) {
        return keyCSP;
    }
    
    return [OFCDSAModule appleCSP];
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
    id <OFCSSMBufferEater> digester;
    xmlOutputBuffer *tee;
    NSError *firstError;
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
        CSSM_DATA cssmbuf = {
            .Data = (void *)buffer,
            .Length = len
        };
        BOOL ok = [context->digester processBuffers:&cssmbuf count:1 error:&(context->firstError)];
        if (!ok)
            return -1;
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
                break;
            cursor = cursor->parent;
        }
        if (cursor == rootElt)
            break;
        cursor = cursor->next;
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

- (BOOL)_verifyReferenceNode:(xmlNode *)referenceNode toBuffer:(xmlOutputBuffer *)outBuf digester:(id <OFCSSMBufferEater>)digester error:(NSError **)outError
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
        OBRejectInvalidCall(self, _cmd, @"Reference index (%lu) is out of range (count is %u)", (unsigned long)nodeIndex, referenceNodeCount);
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
        signatureStructuralFailure(outError, @"The <DigestValue> content is not parsable as base64 data", count);
        return NO;
    }
    id <OFCSSMDigestionContext, NSObject> digester = [self newDigestContextForMethod:digestMethodNode error:outError];
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
    xmlOutputBuffer *buf = xmlAllocOutputBuffer(NULL);
    
    BOOL ok = [self verifyReferenceAtIndex:nodeIndex toBuffer:buf error:outError];
    
    if (ok) {
        NSData *result = [[NSData alloc] initWithBytesNoCopy:buf->buffer->content
                                                      length:buf->buffer->use
                                                freeWhenDone:YES];
        buf->buffer->content = NULL;
        buf->buffer->use = 0;
        buf->buffer->alloc = 0;
        xmlOutputBufferClose(buf);
        
        return [result autorelease];
    } else {
        xmlOutputBufferClose(buf);
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
    id <OFCSSMDigestionContext, NSObject> digester = [self newDigestContextForMethod:digestMethodNode error:outError];
    if (!digester)
        return NO;
    [digester autorelease];
    
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
        
    NSString *digestString = [digestValue base64String];
    
    xmlNode *digestValueNode = OFLibXMLChildNamed(referenceNode, "DigestValue", XMLSignatureNamespace, &count);
    if (count > 1) {
        signatureStructuralFailure(outError, @"Found %d <DigestValue> nodes", count);
        return NO;
    } else if (count == 0) {
        digestValueNode = xmlNewChild(referenceNode, referenceNode->ns,
                                      (const xmlChar *)"DigestValue",
                                      (const xmlChar *)[digestString cStringUsingEncoding:NSUTF8StringEncoding]);
        (void)digestValueNode; /* dead store is OK here */
    } else {
        setNodeContentToString(digestValueNode, digestString);
    }

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
- (id <OFCSSMDigestionContext, NSObject>)newDigestContextForMethod:(xmlNode *)digestMethodNode error:(NSError **)outError;
{
    xmlChar *algid = lessBrokenGetAttribute(digestMethodNode, "Algorithm", XMLSignatureNamespace);
    if (!algid) {
        signatureStructuralFailure(outError, @"No digest algorithm specified");
        return nil;
    }
    
    id <OFCSSMDigestionContext, NSObject> result;
    
    CSSM_ALGORITHMS cssm_algid;
    
    if (xmlStrcmp(algid, XMLDigestSHA1) == 0) {
        cssm_algid = CSSM_ALGID_SHA1;
    } else if (xmlStrcmp(algid, XMLDigestSHA224) == 0) {
        cssm_algid = CSSM_ALGID_SHA224;
    } else if (xmlStrcmp(algid, XMLDigestSHA256) == 0) {
        cssm_algid = CSSM_ALGID_SHA256;
    } else if (xmlStrcmp(algid, XMLDigestSHA384) == 0) {
        cssm_algid = CSSM_ALGID_SHA384;
    } else if (xmlStrcmp(algid, XMLDigestSHA512) == 0) {
        cssm_algid = CSSM_ALGID_SHA512;
    } else if (xmlStrcmp(algid, XMLDigestMD5) == 0) {
        cssm_algid = CSSM_ALGID_MD5;
    } else {
        cssm_algid = CSSM_ALGID_NONE;
    }
    
    if (cssm_algid != CSSM_ALGID_NONE) {
        OFCDSAModule *csp = [OFCDSAModule appleCSP];
        CSSM_CC_HANDLE context = CSSM_INVALID_HANDLE;
        CSSM_RETURN err = CSSM_CSP_CreateDigestContext([csp handle], cssm_algid, &context);
        if (err != CSSM_OK || context == CSSM_INVALID_HANDLE) {
            OFErrorFromCSSMReturn(outError, err, [NSString stringWithFormat:@"CSSM_CSP_CreateDigestContext(algid=%u for <%s>)", (unsigned)cssm_algid, algid]);
            result = nil;
        } else {
            result = [[OFCSSMDigestContext alloc] initWithCSP:csp cc:context];
        }
    } else {
        /* TODO: Figure out best way for subclassers to extend this method */
        signatureValidationFailure(outError, @"Unimplemented digest algorithm <%s>", algid);
        result = nil;
    }
    
    xmlFree(algid);
    return result;
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
- (BOOL)_writeReference:(xmlNode *)reference to:(struct OFXMLSignatureVerifyContinuation *)stream error:(NSError **)outError;
{
    OBASSERT(isNamed(reference, "Reference", XMLSignatureNamespace, NULL));
    
    xmlChar *refURI = lessBrokenGetAttribute(reference, "URI", XMLSignatureNamespace);
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
        xmlChar *refType = lessBrokenGetAttribute(reference, "Type", XMLSignatureNamespace);
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

/*" Subclassers must implement this to find and return the specified asymmetric (RSA or DSA) key. "*/
- (OFCSSMKey *)getPublicKey:(xmlNode *)keyInfo algorithm:(CSSM_ALGORITHMS)algid error:(NSError **)outError
{
    signatureValidationFailure(outError, @"Public key not available");
    return nil;
}

- (OFCSSMKey *)getPrivateKey:(xmlNode *)keyInfo algorithm:(CSSM_ALGORITHMS)algid error:(NSError **)outError
{
    signatureValidationFailure(outError, @"Private key not available");
    return nil;
}

/*" Subclassers must implement this to find and return the specified HMAC key. "*/
- (OFCSSMKey *)getHMACKey:(xmlNode *)keyInfo algorithm:(CSSM_ALGORITHMS)algid error:(NSError **)outError
{
    signatureValidationFailure(outError, @"HMAC key not available");
    return nil;
}

/*" Subclassers must implement this to resolve any external references (that is, <Reference> nodes pointing outside of the containing document). By default, those references are not resolved. "*/
- (BOOL)writeReference:(NSString *)externalReference type:(NSString *)referenceType to:(xmlOutputBuffer *)stream error:(NSError **)outError;
{
    signatureValidationFailure(outError, @"Retrieval of external reference <%@> not supported", externalReference);
    return NO;
}

@end

#pragma mark Key extraction utility functions

/*" This is not a fully featured extraction of the <X509Data> node; it does not return errors, and refuses to parse some valid but weird structurs. Returns a dictionary whose keys are the XML element names with the "X509" prefix removed, and whose values are NSStrings or NSDatas, depending on what makes sense for that element. The <X509SerialNumber> subelement of the <X509IssuerSerial> element is returned under the key IssuerSerialNumber. The <X509Certificate> element may be repeated; the value of the Certificate key is always an NSArray. "*/
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
