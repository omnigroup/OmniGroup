// Copyright 2009-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFXMLSignature.h>
#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <libxml/xpathinternals.h>
#include <getopt.h>

#define OSUAppcastXMLNamespace ((const xmlChar *)"http://www.omnigroup.com/namespace/omniappcast/v1")

// See: http://learn.adobe.com/wiki/display/ADCdocs/Adobe+Appcasting+Namespace+Extension
#define AdobeAppcastNamespace ((const xmlChar *)"http://www.adobe.com/xml-namespaces/appcast/1.0")
// See: http://www.rssboard.org/rss-profile#namespace-elements
#define AtomNamespace ((const xmlChar *)"http://www.w3.org/2005/Atom")
#define DublinCoreNamespace ((const xmlChar *)"http://purl.org/dc/elements/1.1/")

@interface OSUAppcastSignatureGenerate : OFXMLSignature
{
    CFArrayRef keychains;
}
- (void)setKeychains:(CFArrayRef)kc;
@end

struct namespaceRemap {
    xmlNsPtr oldNs;
    xmlNsPtr newNs;
    struct namespaceRemap *next;
};
void combineRedundantNamespaceDeclarations(xmlNode *scanApex, struct namespaceRemap *map);
xmlDoc *createFeedDocumentFromItemTemplate(xmlNode *anItem, xmlNode **feedDocItemPlaceholder);
xmlChar *getItemTrack(xmlXPathContext *xp, xmlNode *it);
static inline xmlNode *addText(xmlNode *node, const char *txt);

void generateAndSign(NSArray *tracklist,
                     const char *feedTemplateFile,
                     CFMutableArrayRef keychains,
                     NSString *outputTemplate,
                     NSMutableArray *toStdout,
                     int argc, char **argv);
void signInPlace(CFMutableArrayRef keychains,
                 int argc, char **argv);

// Only used internally to this program
#define FinalTrackName @"*FINAL*"

int verbose = 0;

static const struct option options[] = {
    { "xml-template", required_argument, NULL, 'T' },
    { "output-filename-template", required_argument, NULL, 'o' },
    { "to-stdout", required_argument, NULL, 'c' },
    { "verbose", no_argument, NULL, 'v' },
    { "keychain", required_argument, NULL, 'k' },
    { "track-order", required_argument, NULL, 't' },
    { "sign-in-place", no_argument, NULL, 'i' },
    { 0, 0, 0, 0 }
};
__attribute__((noreturn))
static void usage(const char *progname, int exitstatus)
{
    fprintf(stderr, "usage: %s [options] inputfiles.xml...\n", progname);
    for(int i = 0; options[i].name; i++)
        fprintf(stderr, "\t-%c | --%s%s\n", options[i].val, options[i].name, options[i].has_arg?" arg":"");
    exit(exitstatus);
}

int main(int argc, char **argv)
{
    int ch;
    
    if (argc == 2 && !strcmp(argv[1], "-V")) {
        puts("$Id$");
        exit(0);
    }
    
    NSString *outputTemplate = nil;
    NSMutableArray *toStdout = [[NSMutableArray alloc] init];
    CFMutableArrayRef keychains = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    NSArray *tracklist = nil;
    NSAutoreleasePool *p;
    const char *feedTemplateFile = NULL;
    int shouldSignInPlace = 0;
    
    p = [[NSAutoreleasePool alloc] init];
    while( (ch = getopt_long(argc, argv, "T:o:c:vk:t:i", options, NULL)) >= 0 ) {
        switch(ch) {
            case 0:
                break;
            case '?':
            default:
                usage(argv[0], 1);
                break;
            case 'v':
                verbose ++;
                break;
            case 'o':
                if (outputTemplate)
                    usage(argv[0], 1);
                else {
                    outputTemplate = [[NSString alloc] initWithUTF8String:optarg];
                    if (![outputTemplate containsString:@"%t"]) {
                        fprintf(stderr, "%s: output template must contain '%%t' to hold track name\n", argv[0]);
                        exit(1);
                    }
                }
                break;
            case 'c':
            {
                NSString *emitTrack = [NSString stringWithUTF8String:optarg];
                if ([NSString isEmptyString:emitTrack])
                    emitTrack = FinalTrackName;
                [toStdout addObject:emitTrack];
                break;
            }
            case 'k':
            {
                SecKeychainRef aKeychain = NULL;
                OSStatus oserr = SecKeychainOpen(optarg, &aKeychain);
                if (oserr != noErr || !aKeychain) {
                    fprintf(stderr, "%s: cannot open: %s (OSStatus = %ld)\n",
                            optarg, [OFStringFromCSSMReturn(oserr) cStringUsingEncoding:NSUTF8StringEncoding], (long)oserr);
                    exit(1);
                }
                SecKeychainStatus kStat = 0;
                oserr = SecKeychainGetStatus(aKeychain, &kStat);
                if (oserr != noErr) {
                    fprintf(stderr, "%s: cannot get status: %s\n",
                            optarg, [OFStringFromCSSMReturn(oserr) cStringUsingEncoding:NSUTF8StringEncoding]);
                    exit(1);
                }
                if (!(kStat & kSecReadPermStatus)) {
                    fprintf(stderr, "%s: No read permission?\n", optarg);
                    exit(1);
                }
                
                CFArrayAppendValue(keychains, aKeychain);
                CFRelease(aKeychain);
                break;
            }
            case 't':
            {
                if (tracklist)
                    usage(argv[0], 1);
                NSString *ts = [NSString stringWithUTF8String:optarg];
                tracklist = [[ts componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]] copy];
                break;
            }
            case 'T':
            {
                if (feedTemplateFile)
                    usage(argv[0], 1);
                feedTemplateFile = optarg;
                break;
            }
            case 'i':
                shouldSignInPlace = 1;
                break;
        }
    }
    
    if (!tracklist)
        tracklist = [[NSArray alloc] initWithObjects:@"sneakypeek", @"beta", @"rc", FinalTrackName, nil];
    
    if (![tracklist containsObject:FinalTrackName])
        tracklist = [[[tracklist autorelease] arrayByAddingObject:FinalTrackName] retain];
        
    [p release];

    if (shouldSignInPlace) {
        if (feedTemplateFile || outputTemplate || [toStdout count]) {
            fprintf(stderr, "%s: sign-in-place can't be specified along with generate-and-sign options\n", argv[0]);
            usage(argv[0], 0);
        }
        signInPlace(keychains, argc, argv);
    } else {
        generateAndSign(tracklist, feedTemplateFile, keychains, outputTemplate, toStdout, argc, argv);
    }
    
    [tracklist release];
    [toStdout release];
    [outputTemplate release];
    CFRelease(keychains);
    keychains = NULL;

#ifdef DEBUG_wiml
    {
        char buf[256];
        snprintf(buf, 255, "leaks %u", (unsigned)getpid());
        system(buf);
    }
#endif
    
    return 0;
}


void generateAndSign(NSArray *tracklist,
                     const char *feedTemplateFile,
                     CFMutableArrayRef keychains,
                     NSString *outputTemplate,
                     NSMutableArray *toStdout,
                     int argc, char **argv)
{
    xmlNode *feedTemplateItemNode = NULL;

    if (![toStdout count] && !outputTemplate) {
        fprintf(stderr, "%s: No output options specified\n", argv[0]);
        usage(argv[0], 1);
    }
    
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
    
    /* Create a dictioonary byTrack which maps track names to arrays into which we will put <item> elements */
    NSMutableDictionary *byTrack = [NSMutableDictionary dictionary];
    {
        CFMutableArrayRef ptrArray = CFArrayCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerArrayCallbacks);
        [byTrack setObject:(id)ptrArray forKey:FinalTrackName];
        CFRelease(ptrArray);
    }
    for (NSString *track in tracklist) {
        track = [track stringByRemovingSurroundingWhitespace];
        if ([NSString isEmptyString:track])
            track = FinalTrackName;
        if (![byTrack objectForKey:track]) {
            CFMutableArrayRef ptrArray = CFArrayCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerArrayCallbacks);
            [byTrack setObject:(id)ptrArray forKey:track];
            CFRelease(ptrArray);
        }
    }
    
    /* Warn about unknown tracks being requested... */
    for(NSString *track in toStdout) {
        if (![byTrack objectForKey:track])
            fprintf(stderr, "%s: unknown track '%s' requested for stdout\n", argv[0], [track cStringUsingEncoding:NSUTF8StringEncoding]);
    }
        
    CFMutableArrayRef docsToFree = CFArrayCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerArrayCallbacks);
    
    xmlParserCtxtPtr ctxt = xmlNewParserCtxt();
    
    if (feedTemplateFile) {
        xmlDoc *feedTemplateDoc = xmlCtxtReadFile(ctxt, feedTemplateFile, NULL,
                                                  XML_PARSE_NOENT | XML_PARSE_NOBLANKS | XML_PARSE_NSCLEAN | XML_PARSE_NOCDATA);
        if (!feedTemplateDoc) {
            xmlErrorPtr e = xmlCtxtGetLastError(ctxt);
            fprintf(stderr, "%s: parser error: %s\n", feedTemplateFile, e->message);
            exit(1);
        }
        
        xmlXPathContextPtr xp = xmlXPathNewContext(feedTemplateDoc);
        xmlXPathObjectPtr nodeset = xmlXPathEvalExpression((const xmlChar *)"//channel/item", xp);
        if (!nodeset) {
            fprintf(stderr, "%s: xpath error: %s\n", feedTemplateFile, xp->lastError.message);
            exit(1);
        }
        if (nodeset->type != XPATH_NODESET || !nodeset->nodesetval || nodeset->nodesetval->nodeNr < 1) {
            fprintf(stderr, "%s: no items found?\n", feedTemplateFile);
            exit(1);
        }
        feedTemplateItemNode = nodeset->nodesetval->nodeTab[0];
        xmlXPathFreeObject(nodeset);
        xmlXPathFreeContext(xp);
        CFArrayAppendValue(docsToFree, feedTemplateDoc);
    }
    
    /* Read all the input files, shuffle the items into the corresponding arrays by track */
    while(optind < argc) {
        const char *filename = argv[optind];
        xmlDoc *f = xmlCtxtReadFile(ctxt, filename, NULL,
                                    XML_PARSE_NOENT | XML_PARSE_NOBLANKS | XML_PARSE_NSCLEAN | XML_PARSE_NOCDATA);
        if (f) {
            xmlXPathContextPtr xp = xmlXPathNewContext(f);
            xmlXPathRegisterNs(xp, (const xmlChar *)"oac", OSUAppcastXMLNamespace);
            xmlXPathObjectPtr nodeset = xmlXPathEvalExpression((const xmlChar *)"//channel/item", xp);
            if (!nodeset) {
                fprintf(stderr, "%s: xpath error: %s\n", filename, xp->lastError.message);
                exit(1);
            }
            if (nodeset->type != XPATH_NODESET || !nodeset->nodesetval || nodeset->nodesetval->nodeNr < 1) {
                fprintf(stderr, "%s: no items found?\n", filename);
            } else {
                if (verbose)
                    fprintf(stderr, "%s: %d items found\n", filename, nodeset->nodesetval->nodeNr);
                for(int i = 0; i < nodeset->nodesetval->nodeNr; i++) {
                    xmlNode *anItem = nodeset->nodesetval->nodeTab[i];
                    xmlChar *thisNodePath = xmlGetNodePath(anItem);
                    char *thisTrackName = (char *)getItemTrack(xp, anItem);
                    
                    if (verbose)
                        fprintf(stderr, "%s: %s track=%s\n", filename, thisNodePath, thisTrackName);
                    
                    NSString *track;
                    if (!thisTrackName || !*thisTrackName)
                        track = FinalTrackName;
                    else
                        track = [NSString stringWithUTF8String:thisTrackName];
                    
                    CFMutableArrayRef itemsOnThisTrack = (void *)[byTrack objectForKey:track];
                    if (!itemsOnThisTrack) {
                        fprintf(stderr, "%s: %s: error: unknown track '%s'\n", filename, thisNodePath, thisTrackName?thisTrackName:"");
                        exit(1);
                    }
                    CFArrayAppendValue(itemsOnThisTrack, anItem);

                    xmlFree(thisNodePath);
                    if (thisTrackName)
                        xmlFree(thisTrackName);
                }
            }
            xmlXPathFreeObject(nodeset);
            xmlXPathFreeContext(xp);
            CFArrayAppendValue(docsToFree, f);
        } else {
            xmlErrorPtr e = xmlCtxtGetLastError(ctxt);
            fprintf(stderr, "%s: parser error: %s\n", filename, e->message);
            exit(1);
        }
        optind ++;
    }
    xmlFreeParserCtxt(ctxt);
    
    CFMutableDictionaryRef combinedFeeds = CFDictionaryCreateMutable(kCFAllocatorDefault, [byTrack count], &OFNSObjectDictionaryKeyCallbacks, &OFNonOwnedPointerDictionaryValueCallbacks);
    
    for(NSString *track in [byTrack allKeys]) {
        CFArrayRef items = (CFArrayRef)[byTrack objectForKey:track];
        if (verbose)
            fprintf(stderr, "track '%s' has %u items\n", [track cStringUsingEncoding:NSUTF8StringEncoding], (unsigned int)CFArrayGetCount(items));
        if(CFArrayGetCount(items) == 0)
            continue;
        
        /* Get a list of all items on this or any more-stable track */
        CFMutableArrayRef mergedItems = CFArrayCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerArrayCallbacks);
        for(NSUInteger trackIndex = [tracklist indexOfObject:track]; trackIndex < [tracklist count]; trackIndex ++) {
            CFArrayRef moreItems = (CFArrayRef)[byTrack objectForKey:[tracklist objectAtIndex:trackIndex]];
            if (moreItems)
                CFArrayAppendArray(mergedItems, moreItems, (CFRange){.location = 0, .length = CFArrayGetCount(moreItems)});
        }
        CFIndex mergedItemCount = CFArrayGetCount(mergedItems);
        
        xmlNode *feedDocItemPlaceholder = NULL;
        xmlDoc *feedDoc;
        if (feedTemplateItemNode) {
            /* There's an explicitly specified template doc; use it */
            feedDoc = createFeedDocumentFromItemTemplate(feedTemplateItemNode, &feedDocItemPlaceholder);
        } else {
            /* Grab the channel element from the first item, use it as a template */
            xmlNode *anItem = (xmlNode *)CFArrayGetValueAtIndex(mergedItems, 0);
            feedDoc = createFeedDocumentFromItemTemplate(anItem, &feedDocItemPlaceholder);
        }
        CFDictionaryAddValue(combinedFeeds, track, feedDoc);
        xmlNode *insertionPoint = feedDocItemPlaceholder;
        for(CFIndex itemIndex = 0; itemIndex < mergedItemCount; itemIndex ++) {
            xmlNode *anItem = (xmlNode *)CFArrayGetValueAtIndex(mergedItems, itemIndex);
            xmlNode *copied = xmlDocCopyNode(anItem, feedDoc, 1 /* 1 = fully recursive copy */ );
            if (itemIndex == 0)
                insertionPoint = addText(insertionPoint, "\n    ");
            else
                insertionPoint = addText(insertionPoint, "    ");
            insertionPoint = xmlAddNextSibling(insertionPoint, copied);
            insertionPoint = addText(insertionPoint, "\n");
        }
        if (feedDocItemPlaceholder->type == XML_COMMENT_NODE) {
            xmlUnlinkNode(feedDocItemPlaceholder);
            xmlFreeNode(feedDocItemPlaceholder);
        }
        combineRedundantNamespaceDeclarations(xmlDocGetRootElement(feedDoc), NULL);
        CFRelease(mergedItems);
    }
    
    byTrack = nil;
    [p release];
    
    while(CFArrayGetCount(docsToFree) > 0) {
        CFIndex last = CFArrayGetCount(docsToFree) - 1;
        xmlDoc *lastValue = (xmlDoc *)CFArrayGetValueAtIndex(docsToFree, last);
        CFArrayRemoveValueAtIndex(docsToFree, last);
        xmlFreeDoc(lastValue);
    }
    CFRelease(docsToFree);
    docsToFree = NULL;
    
    p = [[NSAutoreleasePool alloc] init];
    int fatalityCount = 0;
    for(NSString *track in (NSDictionary *)combinedFeeds) {
        const char *trackCstring = [track cStringUsingEncoding:NSUTF8StringEncoding];
        xmlDoc *feedDoc = (xmlDoc *)CFDictionaryGetValue(combinedFeeds, track);
        NSArray *sigElements = [OSUAppcastSignatureGenerate signaturesInTree:feedDoc];
        if (!sigElements || ![sigElements count]) {
            fprintf(stderr, "%s: warning: no signature elements for track=%s\n", argv[0], trackCstring);
        }
        for(OSUAppcastSignatureGenerate *sig in sigElements) {
            NSError *failWhy = NULL;
            if(keychains && CFArrayGetCount(keychains) > 0)
                [sig setKeychains:keychains];
            BOOL ok = [sig computeReferenceDigests:&failWhy] && [sig processSignatureElement:OFXMLSignature_Sign error:&failWhy];
            if (!ok) {
                fprintf(stderr, "%s: error: unable to sign feed for track=%s\n", argv[0], trackCstring);
                fprintf(stderr, "%s\n%s\n",
                        [[failWhy description] cStringUsingEncoding:NSUTF8StringEncoding],
                        [[[failWhy userInfo] description] cStringUsingEncoding:NSUTF8StringEncoding]);
                fatalityCount ++;
            }
        }
    }
    if (fatalityCount)
        exit(1);
    [p release];
    
    p = [[NSAutoreleasePool alloc] init];
    if (outputTemplate) {
        NSMutableDictionary *expandedTemplates = [NSMutableDictionary dictionary];
        for(NSString *track in tracklist) {
            NSMutableString *outFile = [[outputTemplate mutableCopy] autorelease];
            for(;;) {
                NSRange r = [outFile rangeOfString:@"%t"];
                if (!r.length)
                    break;
                if ([track isEqual:FinalTrackName]) {
                    if (r.location > 0 && [outFile characterAtIndex:(r.location - 1)] == '-') {
                        r.location --;
                        r.length ++;
                    }
                    [outFile deleteCharactersInRange:r];
                } else {
                    [outFile replaceCharactersInRange:r withString:track];
                }
            }
            
            [expandedTemplates setObject:outFile forKey:track];
        }
        
        for(NSString *track in tracklist) {
            NSMutableString *outFile = [expandedTemplates objectForKey:track];
            const char *path = [outFile fileSystemRepresentation];

            xmlDoc *outDoc = (xmlDoc *)CFDictionaryGetValue(combinedFeeds, track);
            
            struct stat sbuf;
            bzero(&sbuf, sizeof(sbuf));
            int sberrno;
            if (lstat(path, &sbuf)) {
                if (errno != ENOENT) {
                    perror(path);
                    exit(2);
                }
                sberrno = errno;
            } else
                sberrno = 0;
                
            if (outDoc) {
                if (verbose)
                    fprintf(stderr, "writing track %s -> %s\n", [track cStringUsingEncoding:NSUTF8StringEncoding], path);
                if (sberrno == ENOENT) {
                    /* OK */
                } else if (S_ISLNK(sbuf.st_mode) || (S_ISREG(sbuf.st_mode) && (sbuf.st_nlink > 1))) {
                    if(unlink(path)) {
                        perror(path);
                        exit(2);
                    }
                }
                FILE *outfile = fopen(path, "w");
                if (!outfile) {
                    perror(path);
                    exit(2);
                }
                if (xmlDocDump(outfile, outDoc) < 0) {
                    fprintf(stderr, "xmlDocDump() had an error writing to %s?\n", path);
                    fatalityCount ++;
                }
                fclose(outfile);
            } else {
                if (sberrno != ENOENT) {
                    if(unlink(path)) {
                        perror(path);
                        exit(2);
                    }
                }
                
                NSUInteger desiredTrack = [tracklist indexOfObject:track];
                while(desiredTrack < [tracklist count] &&
                      !CFDictionaryContainsKey(combinedFeeds, [tracklist objectAtIndex:desiredTrack]))
                    desiredTrack ++;
                
                if (desiredTrack < [tracklist count]) {
                    const char *toPath = [[[expandedTemplates objectForKey:[tracklist objectAtIndex:desiredTrack]] lastPathComponent] fileSystemRepresentation];
                    if (verbose)
                        fprintf(stderr, "linking track %s -> %s\n", path, toPath);
                    if (symlink(toPath, path)) {
                        perror(path);
                        fatalityCount ++;
                    }
                }
            }
        }
    }
    
    for(NSString *track in toStdout) {
        NSUInteger desiredTrack = [tracklist indexOfObject:track];
        while(desiredTrack < ([tracklist count]-1) &&
              !CFDictionaryContainsKey(combinedFeeds, [tracklist objectAtIndex:desiredTrack]))
            desiredTrack ++;
        
        xmlDoc *outDoc = (xmlDoc *)CFDictionaryGetValue(combinedFeeds, [tracklist objectAtIndex:desiredTrack]);
        xmlDocDump(stdout, outDoc);
    }
    
    {
        CFIndex n = CFDictionaryGetCount(combinedFeeds);
        const void **docs = malloc(sizeof(*docs) * n);
        CFDictionaryGetKeysAndValues(combinedFeeds, NULL, docs);
        CFDictionaryRemoveAllValues(combinedFeeds);
        for(CFIndex i = 0; i < n; i ++) {
            xmlFreeDoc((void *)docs[i]);
        }
        free(docs);
    }
    
    CFRelease(combinedFeeds);
    [p release];
}

void signInPlace(CFMutableArrayRef keychains,
                 int argc, char **argv)
{
    xmlParserCtxtPtr ctxt = xmlNewParserCtxt();
        
    while(optind < argc) {
        const char *filename = argv[optind];
        xmlDoc *feedDoc = xmlCtxtReadFile(ctxt, filename, NULL,
                                    XML_PARSE_NOENT | XML_PARSE_NOBLANKS | XML_PARSE_NSCLEAN | XML_PARSE_NOCDATA);
        if (!feedDoc) {
            xmlErrorPtr e = xmlCtxtGetLastError(ctxt);
            fprintf(stderr, "%s: parser error: %s\n", filename, e->message);
            exit(1);
        }
        NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
        int failures = 0;
        int shouldRegenerate = 0;
        
        /* Re-generate any signatures which are broken */
        NSArray *sigElements = [OSUAppcastSignatureGenerate signaturesInTree:feedDoc];
        if (!sigElements || ![sigElements count]) {
            fprintf(stderr, "%s: warning: no signature elements found in %s\n", argv[0], filename);
        }
        for(OSUAppcastSignatureGenerate *sig in sigElements) {
            NSError *failWhy = NULL;
            if(keychains && CFArrayGetCount(keychains) > 0)
                [sig setKeychains:keychains];
            
            if (![sig processSignatureElement:OFXMLSignature_Verify error:&failWhy]) {
                if ([[failWhy domain] isEqualToString:OFXMLSignatureErrorDomain] &&
                    [failWhy code] == OFXMLSignatureValidationFailure) {
                    shouldRegenerate ++;
                    NSLog(@" %@ %@", failWhy, [failWhy userInfo]);
                } else
                    failures ++;
            }
        }
        
        if (failures) {
            fprintf(stderr, "%s: error checking %s\n", argv[0], filename);
        } else if (!shouldRegenerate) {
            fprintf(stderr, "%s: signature is still valid on %s\n", argv[0], filename);
        } else {
            fprintf(stderr, "%s: generating signatures in %s\n", argv[0], filename);
            NSArray *sigElements = [OSUAppcastSignatureGenerate signaturesInTree:feedDoc];
            for(OSUAppcastSignatureGenerate *sig in sigElements) {
                NSError *failWhy = NULL;

                BOOL ok = [sig computeReferenceDigests:&failWhy] && [sig processSignatureElement:OFXMLSignature_Sign error:&failWhy];

                if (!ok) {
                    fprintf(stderr, "%s: error: unable to sign feed %s\n", argv[0], filename);
                    fprintf(stderr, "%s\n%s\n",
                            [[failWhy description] cStringUsingEncoding:NSUTF8StringEncoding],
                            [[[failWhy userInfo] description] cStringUsingEncoding:NSUTF8StringEncoding]);
                    failures ++;
                }
            }
            
            if (!failures) {
                FILE *outfile = fopen(filename, "w");
                if (!outfile) {
                    perror(filename);
                    exit(2);
                }
                if (xmlDocDump(outfile, feedDoc) < 0) {
                    fprintf(stderr, "xmlDocDump() had an error writing to %s\n", filename);
                    failures ++;
                }
                fclose(outfile);
            }
        }
        
        [p release];
        xmlFreeDoc(feedDoc);
        if (failures)
            exit(1);
        
        optind ++;
    }

    xmlFreeParserCtxt(ctxt);
}

#pragma mark Utility routines

xmlChar *getItemTrack(xmlXPathContext *xp, xmlNode *it)
{
    xp->node = it;
    xmlXPathObjectPtr trackelt = xmlXPathEvalExpression((const xmlChar *)"./oac:updateTrack", xp);
    if (!trackelt) {
        return NULL;
    } else if (trackelt->type == XPATH_UNDEFINED) {
        xmlXPathFreeObject(trackelt);
        return NULL;
    } else {
        xmlChar *trackstring = xmlXPathCastToString(trackelt);
        xmlXPathFreeObject(trackelt);
        return trackstring;
    }
}

static inline xmlNode *addText(xmlNode *node, const char *txt)
{
    xmlNode *textNode = xmlNewDocText(node->doc, (const xmlChar *)txt);
    return xmlAddNextSibling(node, textNode);
}

static inline BOOL isEltNamed(xmlNode *p, const char *n)
{
    return (p && p->type == XML_ELEMENT_NODE && !strcmp((const char *)(p->name), n));
}

static int nodeDepth(xmlNode *n)
{
    assert(n != NULL);
    assert(n->type == XML_ELEMENT_NODE);
    
    int count = 0;
    xmlNode *p = n->parent;
    while(p && (p->type == XML_ELEMENT_NODE)) {
        count ++;
        p = p->parent;
    }
    
    return count;
}

void doRemap(xmlNs **slot, struct namespaceRemap *map) 
{
    xmlNs *nsUse = *slot;
    if (nsUse) {
        while(map) {
            if (map->oldNs == nsUse) {
                *slot = map->newNs;
                return;
            }
            map = map->next;
        }
    }
}
void combineRedundantNamespaceDeclarations(xmlNode *scanApex, struct namespaceRemap *map)
{
    struct namespaceRemap *submap = map;
    xmlNs *definedHere;
    struct namespaceRemap *mapcursor;
    xmlAttr *attrCursor;
    xmlNode *childCursor;
    
    /* Check to see if any namespaces declared here should be remapped */
    for(definedHere = scanApex->nsDef; definedHere != NULL; definedHere = definedHere->next) {
        if (scanApex->parent != NULL && scanApex->parent->type == XML_ELEMENT_NODE) {
            xmlNs *alternative = xmlSearchNsByHref(scanApex->doc, scanApex->parent, definedHere->href);
            if (!alternative)
                continue;
            if (definedHere->prefix == NULL && alternative->prefix != NULL) {
                /* Don't modify default namespaces (unless combining them with another default namespace) */
                continue;
            }
            
            struct namespaceRemap *addition = malloc(sizeof(*addition));
            addition->oldNs = definedHere;
            addition->newNs = alternative;
            addition->next = submap;
            submap = addition;
        }
    }
    
    /* If we eliminated a locally defined namespace, remove its definition */
    for(mapcursor = submap; mapcursor != map; mapcursor = mapcursor->next) {
        xmlNs **definedWhere = &( scanApex->nsDef );
        while(*definedWhere) {
            if ((*definedWhere) == mapcursor->oldNs) {
                *definedWhere = (*definedWhere)->next;
            } else {
                definedWhere = &( (*definedWhere)->next );
            }
        }
    }
    
    /* Replace all namespaces on non-element content */
    doRemap(&(scanApex->ns), submap);
    for (attrCursor = scanApex->properties; attrCursor; attrCursor = attrCursor->next) {
        doRemap(&(attrCursor->ns), submap);
    }
    
    /* Replace all namespaces on child elements */
    for (childCursor = scanApex->children; childCursor; childCursor = childCursor->next) {
        if (childCursor->type == XML_ELEMENT_NODE)
            combineRedundantNamespaceDeclarations(childCursor, submap);
    }
    
    /* Clean up our remap list */
    while (submap != map) {
        struct namespaceRemap *old = submap;
        submap = submap->next;
        xmlFreeNs(old->oldNs);
        free(old);
    }
}

xmlDoc *createFeedDocumentFromItemTemplate(xmlNode *anItem, xmlNode **feedDocItemPlaceholder)
{
    xmlDoc *newDoc = xmlNewDoc((const xmlChar *)"1.0");
    xmlNode *placeholder = NULL;
    
    int itemDepth = nodeDepth(anItem);
    // itemDepth is equal to the number of parent elements that the <item> node has.
    
    xmlNode *tip = NULL;
    for(int depth = 0; depth < itemDepth; depth ++) {
        xmlNode *cloneThis = anItem;
        for(int count = 0; count+depth < itemDepth; count ++)
            cloneThis = cloneThis->parent;
        
        xmlNode *cloned = xmlDocCopyNode(cloneThis, newDoc, 2 /* 2 = copy attributes etc. but not child elts */ );
        
        if (isEltNamed(cloned, "channel")) {
            xmlNode *p = cloneThis->children;
            while(p) {
                if (p == anItem) {
                    if (!placeholder) {
                        /* Insert a placeholder for <item>s, and return it */
                        placeholder = xmlNewDocComment(newDoc, (const xmlChar *)" releases ");
                        xmlAddChild(cloned, placeholder);
                    }
                } else if (p->type == XML_ELEMENT_NODE && !isEltNamed(p, "item")  && !isEltNamed(p, "lastBuildDate")) {
                    /* Copy all non-<item> child elements of the <channel> element as well. */
                    xmlNode *alsoCloneThis = xmlDocCopyNode(p, newDoc, 1 /* 1 = deep copy */ );
                    xmlAddChild(cloned, alsoCloneThis);
                }
                p = p->next;
            }
            
            /* Add lastBuildDate */
            {
                char buf[128];
                time_t now;
                struct tm timebuf;
                bzero(&timebuf, sizeof(timebuf));
                time(&now);
                size_t timelen = strftime(buf, 127, "%a, %e %b %Y %T %Z", gmtime_r(&now, &timebuf));
                if (timelen) {
                    xmlNode *stamp = xmlNewNode(NULL, (const xmlChar *)"lastBuildDate");
                    xmlNodeSetContent(stamp, (const xmlChar *)buf);
                    if (placeholder)
                        xmlAddPrevSibling(placeholder, stamp);
                    else
                        xmlAddChild(cloned, stamp);
                }
            }            
        }
        
        if (tip == NULL)
            xmlDocSetRootElement(newDoc, cloned);
        else
            xmlAddChild(tip, cloned);
        tip = cloned;
    }
    
    combineRedundantNamespaceDeclarations(xmlDocGetRootElement(newDoc), NULL);
    
    *feedDocItemPlaceholder = placeholder;
    
    return newDoc;
}

@implementation OSUAppcastSignatureGenerate

// Init and dealloc

- init;
{
    if ([super init] == nil)
        return nil;
    
    return self;
}

- (void)dealloc;
{
    if (keychains)
        CFRelease(keychains);
    [super dealloc];
}

- (void)setKeychains:(CFArrayRef)kc;
{
    if (kc)
        CFRetain(kc);
    if(keychains)
        CFRelease(keychains);
    keychains = kc;
}

- (OFCSSMKey *)getPrivateKey:(xmlNode *)keyInfo algorithm:(CSSM_ALGORITHMS)keytype error:(NSError **)outError;
{
    NSMutableDictionary *errorInfo = [NSMutableDictionary dictionary];
    CFMutableArrayRef auxCertificates = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    NSArray *testCertificates = OFXMLSigFindX509Certificates(keyInfo, auxCertificates, errorInfo);
    CFRelease(auxCertificates);
    
    SecIdentityRef signer = NULL;
    OSStatus err = noErr;
    
    for(id cert in testCertificates) {
        signer = NULL;
        err = SecIdentityCreateWithCertificate(keychains, (SecCertificateRef)cert, &signer);
        if (err == noErr)
            break;
        else {
            NSError *subError = NULL;
            OFErrorFromCSSMReturn(&subError, err, @"SecIdentityCreateWithCertificate");
            [errorInfo setObject:subError forKey:NSUnderlyingErrorKey];
        }
    }
    
    if (signer == NULL) {
        if (outError) {
            [errorInfo setObject:@"Could not find signing identity" forKey:NSLocalizedDescriptionKey];
            *outError = [NSError errorWithDomain:OFXMLSignatureErrorDomain code:OFXMLSignatureValidationFailure userInfo:errorInfo];
        }
        return nil;
    }
    
    SecKeyRef privKey = NULL;
    err = SecIdentityCopyPrivateKey(signer, &privKey);
    if (err) {
        OFErrorFromCSSMReturn(outError, err, @"SecIdentityCopyPrivateKey");
        return nil;
    }
    
    CFRelease(signer);
    
    OFCSSMKey *result = [OFCSSMKey keyFromKeyRef:privKey error:outError];
    if (!result) {
        CFRelease(privKey);
        return nil;
    }
    
    const CSSM_ACCESS_CREDENTIALS *creds = NULL;
    err = SecKeyGetCredentials(privKey, CSSM_ACL_AUTHORIZATION_SIGN, kSecCredentialTypeDefault, &creds);
    if (err != noErr) {
        OFErrorFromCSSMReturn(outError, err, @"SecKeyGetCredentials");
        CFRelease(privKey);
        return nil;
    }
    [result setCredentials:creds];
    
    CFRelease(privKey);
    return result;
}


@end


