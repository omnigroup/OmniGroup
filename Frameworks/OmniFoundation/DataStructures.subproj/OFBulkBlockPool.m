// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBulkBlockPool.h>

RCS_ID("$Id$")

size_t _OFBulkBlockPageSize;


void  OFBulkBlockPoolInitialize(OFBulkBlockPool *pool, size_t blockSize)
{
    OBPRECONDITION(blockSize <= NSPageSize() - sizeof(OFBulkBlockPage));
                     
    // We set this each time -- doesn't really hurt anything
    _OFBulkBlockPageSize = NSPageSize();
    
    pool->pages          = NULL;
    pool->currentPage    = NULL;
    pool->pageCount      = 0;
    pool->blockSize      = blockSize;
    pool->freeList       = NULL;

    pool->allocationSize = (blockSize / sizeof(unsigned int)) * sizeof(unsigned int);
    if (pool->allocationSize * sizeof(unsigned int) < pool->blockSize)
        pool->allocationSize += sizeof(unsigned int);
}

void _OFBulkBlockPoolGetPage(OFBulkBlockPool *pool)
{
    OBPRECONDITION(!pool->freeList);
    
    if (pool->currentPage)
        // Update the page that we were dealing with
        pool->currentPage->freeList = NULL;

    // See if we have another page that has some free blocks
    if (pool->pages) {
        // We could start from the currentPage and loop around, but that would be more error prone.  This will cause full pages to get swapped in when they might not otherwise.
        unsigned int pageIndex;

        for (pageIndex = 0; pageIndex < pool->pageCount; pageIndex++) {
            if (pool->pages[pageIndex]->freeList) {
                pool->currentPage = pool->pages[pageIndex];
                pool->freeList    = pool->currentPage->freeList;
                break;
            }
        }
    }

    if (!pool->freeList) {
        void *block, *blockEnd;
        
        // There were no non-full pages
        // Make room to store another page
        pool->pageCount++;
        if (pool->pages)
            pool->pages = NSZoneRealloc(NSDefaultMallocZone(), pool->pages, sizeof(void *) * pool->pageCount);
        else
            pool->pages = NSZoneMalloc(NSDefaultMallocZone(), sizeof(void *) * pool->pageCount);

        // Allocate the page
        OBASSERT(_OFBulkBlockPageSize);
        pool->currentPage       = NSAllocateMemoryPages(_OFBulkBlockPageSize);
#ifdef DEBUG_PAGES
        fprintf(stderr, "pool %p allocated page %p\n", pool, pool->currentPage);
#endif
        
        pool->currentPage->pool = pool;
        pool->pages[pool->pageCount-1] = pool->currentPage;

        // Set up the free list in the new page
        block                       = &pool->currentPage->data[0];
        blockEnd                    = (void *)pool->currentPage + _OFBulkBlockPageSize - pool->allocationSize;
        pool->currentPage->freeList = block;

        //fprintf(stderr, "Block = 0x%08x, blockSize = %d, allocationSize = %d\n", block, pool->blockSize, pool->allocationSize);
        while (block <= blockEnd) {
            void *nextBlock;

            nextBlock = block + pool->allocationSize;
            *(void **)block = nextBlock;
            block = nextBlock;

            //fprintf(stderr, "  block = 0x%08x\n", block);
        }

        // Terminate the free list -- probably not necessary since we just did a low level page allocation, but it can't really hurt.
        //fprintf(stderr, "  blockEnd = 0x%08x\n", blockEnd);
        block -= pool->allocationSize;                   // back up to the last block
        OBASSERT((blockEnd - block) < (ptrdiff_t)pool->allocationSize); // there should not be a whole block left
        *(void **)block = NULL;                          // terminate the list

        // Cache the freeList
        pool->freeList = pool->currentPage->freeList;
    }
        
    OBPOSTCONDITION(pool->currentPage);
    OBPOSTCONDITION(pool->freeList);
    OBPOSTCONDITION(pool->currentPage->freeList == pool->freeList);
}

void OFBulkBlockPoolDeallocateAllBlocks(OFBulkBlockPool *pool)
{
    // Later, when we support user-defined allocation events, we'll need to do something cooler here
    if (pool->pages) {
        unsigned int pageIndex;
        
        OBASSERT(pool->pageCount);
        OBASSERT(pool->currentPage);

        for (pageIndex = 0; pageIndex < pool->pageCount; pageIndex++) {
            NSDeallocateMemoryPages(pool->pages[pageIndex], _OFBulkBlockPageSize);
#ifdef DEBUG_PAGES
            fprintf(stderr, "pool 0x%08x deallocated page 0x%08x\n", pool, pool->pages[pageIndex]);
#endif
        }


        NSZoneFree(NSDefaultMallocZone(), pool->pages);
        
        pool->pages       = NULL;
        pool->currentPage = NULL;
        pool->pageCount   = 0;
        pool->freeList    = NULL;
    }
}

void OFBulkBlockPoolReportStatistics(OFBulkBlockPool *pool)
{
    NSUInteger pageIndex;
    NSUInteger blocksPerPage;

    blocksPerPage = (NSPageSize() - sizeof(OFBulkBlockPage)) / pool->allocationSize;
    
    fprintf(stderr, "pool = %p\n", (void *)pool);
    fprintf(stderr, "  number of pages       = %" PRIiPTR "\n", pool->pageCount);
    fprintf(stderr, "  bytes per block       = %" PRIiPTR " (%" PRIiPTR " allocated)\n", pool->blockSize, pool->allocationSize);
    fprintf(stderr, "  blocks per page       = %" PRIiPTR "\n", blocksPerPage);
    fprintf(stderr, "  wasted bytes per page = %" PRIiPTR "\n", (size_t)NSPageSize() - blocksPerPage * pool->blockSize);

    for (pageIndex = 0; pageIndex < pool->pageCount; pageIndex++) {
        OFBulkBlockPage *page;
        NSUInteger freeCount;
        void *freeBlock;
        
        page = pool->pages[pageIndex];
        freeCount = 0;

        if (page == pool->currentPage)
            freeBlock = pool->freeList;
        else
            freeBlock = page->freeList;
        while (freeBlock) {
            freeBlock = *(void **)freeBlock;
            freeCount++;
        }

        fprintf(stderr, "  page = %p, free blocks = %" PRIiPTR ", allocated blocks = %" PRIiPTR "\n", (void *)page, freeCount, blocksPerPage - freeCount);
    }
}

#ifdef TEST

static BOOL OFBulkBlockPoolCheckFreeLists(OFBulkBlockPool *pool)
{
    unsigned int pageIndex;
    OFBulkBlockPage *page;
    void *freeBlock;

    for (pageIndex = 0; pageIndex < pool->pageCount; pageIndex++) {
        page = pool->pages[pageIndex];
        if (page == pool->currentPage)
            freeBlock = pool->freeList;
        else
            freeBlock = page->freeList;
        
        while (freeBlock) {
            OBASSERT(((void *)freeBlock - (void *)page) < (ptrdiff_t)_OFBulkBlockPageSize);
            freeBlock = *(void **)freeBlock;
        }
    }

    return YES;
}

#endif
